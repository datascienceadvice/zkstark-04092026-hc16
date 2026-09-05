//! bench: воспроизводимый прогон zk-протокола сравнения двух групп.
//!
//! Протокол на сценарий (6 доказательств):
//!   lab R1(гр.1) → lab R1(гр.2) → agg S1 → lab R2(гр.1) → lab R2(гр.2) → agg S2
//! Каждый receipt верифицируется; все метрики доказуемо совпадают с golden
//! (R 4.3.1) в пределах заданного допуска. Результат — в SQLite + CSV.

mod data;
mod db;
mod export;
mod runner;
mod types;

use data::{load_golden, load_scenarios};
use db::{CaseRunRow, Db};
use export::export_run;
use runner::run_all;
use std::env;
use std::process::Command;

fn usage() -> ! {
    eprintln!(
        "bench: zk-протокол сравнения двух групп (аргументы через пробел)\n\
        \x20 --mode dev|full   (dev = fake receipts, journal настоящий; default dev)\n\
        \x20 --cases all|a,b   (подмножество сценариев; default all)\n\
        \x20 --tol 1e-9        (допуск rel-ошибки для golden-проверок)\n\
        \x20 --db  PATH        (SQLite; default results/zkstark.db)\n\
        \x20 --export          (писать report.csv + errors.csv рядом с БД)"
    );
    std::process::exit(2);
}

fn git_commit() -> String {
    Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| "unknown".into())
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let mut mode = "dev".to_string();
    let mut cases: Option<Vec<String>> = None;
    let mut tol = 1e-9_f64;
    let mut db_path = "results/zkstark.db".to_string();
    let mut do_export = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--mode" => {
                i += 1;
                mode = args[i].clone();
            }
            "--cases" => {
                i += 1;
                cases = Some(args[i].split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect());
            }
            "--tol" => {
                i += 1;
                tol = args[i].parse().unwrap_or_else(|_| usage());
            }
            "--db" => {
                i += 1;
                db_path = args[i].clone();
            }
            "--export" => do_export = true,
            "--export-run" => {
                i += 1;
                let rid: i64 = args[i].parse().unwrap_or_else(|_| usage());
                let conn = rusqlite::Connection::open(&db_path).unwrap();
                let base = db_path.rsplit_once(['/', '\\']).map(|(d, _)| d).unwrap_or(".").to_string();
                export_run(&conn, rid, &base).unwrap();
                println!("экспорт run {rid}: {base}");
                std::process::exit(0);
            }
            _ => usage(),
        }
        i += 1;
    }
    if mode != "dev" && mode != "full" {
        usage();
    }

    if mode == "dev" {
        env::set_var("RISC0_DEV_MODE", "1");
        println!("режим: dev (fake receipts, journal честный)");
    } else {
        env::remove_var("RISC0_DEV_MODE");
        println!("режим: full (настоящие STARK-доказательства)");
    }

    let mut scenarios = load_scenarios("results/scenarios.csv", "results/scenario_meta.csv")
        .unwrap_or_else(|e| {
            eprintln!("scenarios: {e}");
            std::process::exit(1);
        });
    if let Some(wanted) = cases {
        scenarios.retain(|s| wanted.contains(&s.id));
    }
    let golden = load_golden("results/golden.csv").unwrap_or_else(|e| {
        eprintln!("golden: {e}");
        std::process::exit(1);
    });

    // ---- прогон ----
    let runs = run_all(&scenarios, &golden, tol);

    // ---- DB ----
    let db = Db::open(&db_path).unwrap_or_else(|e| {
        eprintln!("db: {e}");
        std::process::exit(1);
    });
    for s in &scenarios {
        db.upsert_scenario(&s.id, &s.name, s.alpha, s.group1.len(), s.group2.len())
            .unwrap();
    }
    if runs.iter().any(|r| r.status == "ok") {
        let now = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string();
        let run_id = db.begin_run(&now, &mode, &git_commit()).unwrap();
        let mut n_pass = 0;
        for r in &runs {
            let sw1 = |metric: &str| r.checks.iter().find(|c| c.metric == metric).map(|c| c.got);
            let row = CaseRunRow {
                scenario: r.scenario.clone(),
                status: r.status.clone(),
                method: r.method.map(|m| match m {
                    types::MethodOutcome::Welch => "welch".to_string(),
                    types::MethodOutcome::Mood => "mood".to_string(),
                }),
                sw1_w: sw1("sw1.w"),
                sw1_p: sw1("sw1.p"),
                sw2_w: sw1("sw2.w"),
                sw2_p: sw1("sw2.p"),
                welch_t: sw1("welch.t"),
                welch_df: sw1("welch.df"),
                welch_p: sw1("welch.p"),
                m_hat: sw1("m_hat"),
                mood_a: r.checks.iter().find(|c| c.metric == "mood.a").map(|c| c.got as u64),
                mood_b: r.checks.iter().find(|c| c.metric == "mood.b").map(|c| c.got as u64),
                mood_p: sw1("mood.p"),
                total_cycles: r.total_cycles,
                user_cycles: r.user_cycles,
                segments: r.segments as u64,
                wall_ms: r.prove_wall_ms,
                asserts: r.checks.len() as u64,
                max_rel_err: Some(r.max_rel_err),
                pass: r.pass,
                error_msg: r.error_msg.clone(),
            };
            let case_run_id = db.insert_case_run(run_id, &row).unwrap();
            for c in &r.checks {
                if c.rel_err > tol {
                    db.insert_assertion_error(case_run_id, &c.metric, c.expected, c.got, c.rel_err)
                        .unwrap();
                }
            }
            if r.pass {
                n_pass += 1;
            }
            println!(
                "{:<5} {:<8} method={:<7} checks={:<3} max_rel_err={:.3e} pass={} wall={}ms cycles={}",
                r.scenario,
                r.status,
                r.method.map(|m| format!("{m:?}")).unwrap_or_else(|| "-".into()),
                r.checks.len(),
                r.max_rel_err,
                r.pass,
                r.prove_wall_ms,
                r.total_cycles,
            );
        }
        println!("run_id={run_id} ok/всего {n_pass}/{} сценариев", runs.len());

        if do_export {
            let base = db_path.rsplit_once(['/', '\\']).map(|(d, _)| d).unwrap_or(".").to_string();
            let conn = rusqlite::Connection::open(&db_path).unwrap();
            export_run(&conn, run_id, &base).unwrap();
            println!("экспорт: {}/*{run_id}.csv", base);
        }
    } else {
        println!("нет исполнимых сценариев (все expected_error или ошибки)");
        for r in &runs {
            println!("{}: {} ({:?})", r.scenario, r.status, r.error_msg);
        }
    }
}