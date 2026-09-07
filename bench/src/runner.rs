//! Исполнение zk-протокола для одного сценария:
//!   lab R1(группа1) → lab R1(группа2) → agg S1 → lab R2(группа1) → lab R2(группа2) → agg S2
//! Каждый receipt доказывается и верифицируется; метрики journal сверяются с golden.

use crate::data::golden as golden_of;
use crate::types::{CaseRun, Check, GoldenValues, MethodOutcome, Scenario};
use methods::{AGGREGATOR_ELF, AGGREGATOR_ID, LAB_ELF, LAB_ID};
use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};
use serde::Serialize;
use std::time::Instant;
use zkstark_core::{
    analyze, AggInput, AggOutput, LabInput, LabOutput, RawSample, Stage1Decision,
};

struct ProofStat {
    wall_ms: u64,
    total_cycles: u64,
    user_cycles: u64,
    segments: usize,
}

/// Доказывает elf с input (+ предположения-лаборатории), верифицирует receipt
/// по method_id и декодирует journal. Композиция Risc Zero: агрегатору
/// передаются receipt'ы лабораторных программ через `assumptions` — они
/// подмешиваются в env для разрешения `env::verify` внутри гостя.
#[allow(clippy::type_complexity)]
fn prove_with<T>(
    elf: &[u8],
    method_id: [u32; 8],
    input: &impl Serialize,
    assumptions: &[Receipt],
) -> Result<(T, ProofStat, Receipt), String>
where
    T: serde::de::DeserializeOwned,
{
    let mut builder = ExecutorEnv::builder();
    builder
        .write(input)
        .map_err(|e| format!("write input: {e}"))?;
    for r in assumptions {
        builder.add_assumption(r.clone());
    }
    let env = builder.build().map_err(|e| format!("build env: {e}"))?;
    let prover = default_prover();
    let t0 = Instant::now();
    let info = prover.prove(env, elf).map_err(|e| format!("prove: {e}"))?;
    let wall_ms = t0.elapsed().as_millis() as u64;
    let stat = ProofStat {
        wall_ms,
        total_cycles: info.stats.total_cycles,
        user_cycles: info.stats.user_cycles,
        segments: info.stats.segments,
    };
    info.receipt
        .verify(method_id)
        .map_err(|e| format!("verify receipt: {e}"))?;
    let out: T = info
        .receipt
        .journal
        .decode()
        .map_err(|e| format!("decode journal: {e}"))?;
    Ok((out, stat, info.receipt))
}

/// Относительная ошибка ~ |got-exp|/|exp| (для exp==0 — абсолютная).
fn rel_err(got: f64, exp: f64) -> f64 {
    if exp.is_nan() {
        if got.is_nan() { 0.0 } else { f64::INFINITY }
    } else if exp == 0.0 {
        got.abs()
    } else {
        (got - exp).abs() / exp.abs()
    }
}

struct Checks {
    list: Vec<Check>,
    max: f64,
    n: usize,
}

impl Checks {
    fn new() -> Self {
        Self { list: Vec::new(), max: 0.0, n: 0 }
    }
    fn add(&mut self, metric: &str, got: f64, exp: f64) {
        let e = rel_err(got, exp);
        if e > self.max {
            self.max = e;
        }
        self.n += 1;
        self.list.push(Check {
            metric: metric.to_string(),
            expected: exp,
            got,
            rel_err: e,
        });
    }
    fn add_exact(&mut self, metric: &str, got: f64, exp: f64) {
        let e = if got == exp { 0.0 } else { f64::INFINITY };
        if e > self.max {
            self.max = e;
        }
        self.n += 1;
        self.list.push(Check {
            metric: metric.to_string(),
            expected: exp,
            got,
            rel_err: e,
        });
    }
}

fn err_run(scenario: &str, msg: String) -> CaseRun {
    CaseRun {
        scenario: scenario.to_string(),
        status: "error".into(),
        error_msg: Some(msg),
        method: None,
        checks: vec![],
        prove_wall_ms: 0,
        total_cycles: 0,
        user_cycles: 0,
        segments: 0,
        max_rel_err: 0.0,
        pass: false,
    }
}

fn add_stat(wall: &mut u64, cyc: &mut u64, usr: &mut u64, seg: &mut usize, s: &ProofStat) {
    *wall += s.wall_ms;
    *cyc += s.total_cycles;
    *usr += s.user_cycles;
    *seg += s.segments;
}

/// Полный zk-прогон одного сценария (сверка с golden, допуск tol).
pub fn run_case(case: &Scenario, golden: &GoldenValues, tol: f64) -> CaseRun {
    let mut checks = Checks::new();
    let mut wall = 0u64;
    let mut cyc = 0u64;
    let mut usr = 0u64;
    let mut seg = 0usize;
    let g1 = &case.group1;
    let g2 = &case.group2;
    let alpha = case.alpha;
    let gg = |metric: &str| golden_of(golden, &case.id, metric);
    let gid = case.id.clone();

    // lab round 1 (обе группы): receipt'ы лабораторий передаются агрегатору как
    // предположения (композиция) + их журналы попадают во вход агрегатора.
    let (lab_output1, lab_receipt1) = match prove_with(
        LAB_ELF, LAB_ID, &LabInput::Round1(RawSample { values: g1.clone() }), &[],
    ) {
        Ok((o, s, r)) => {
            add_stat(&mut wall, &mut cyc, &mut usr, &mut seg, &s);
            (o, r)
        }
        Err(e) => return err_run(&gid, format!("lab R1(1): {e}")),
    };
    let LabOutput::Round1(lab1) = lab_output1 else {
        return err_run(&gid, "lab R1(1): не Round1".into());
    };

    let (lab_output2, lab_receipt2) = match prove_with(
        LAB_ELF, LAB_ID, &LabInput::Round1(RawSample { values: g2.clone() }), &[],
    ) {
        Ok((o, s, r)) => {
            add_stat(&mut wall, &mut cyc, &mut usr, &mut seg, &s);
            (o, r)
        }
        Err(e) => return err_run(&gid, format!("lab R1(2): {e}")),
    };
    let LabOutput::Round1(lab2) = lab_output2 else {
        return err_run(&gid, "lab R1(2): не Round1".into());
    };

    // aggregator stage 1 — композиция: агрегатор проверяет журналы лабораторий
    let agg1 = match prove_with(
        AGGREGATOR_ELF,
        AGGREGATOR_ID,
        &AggInput::Stage1 {
            lab1: lab1.clone(),
            lab2: lab2.clone(),
            alpha,
            lab1_journal: lab_receipt1.journal.bytes.clone(),
            lab2_journal: lab_receipt2.journal.bytes.clone(),
        },
        &[lab_receipt1.clone(), lab_receipt2.clone()],
    ) {
        Ok((o, s, _r)) => {
            add_stat(&mut wall, &mut cyc, &mut usr, &mut seg, &s);
            o
        }
        Err(e) => return err_run(&gid, format!("agg S1: {e}")),
    };
    let AggOutput::Stage1(decision) = agg1 else {
        return err_run(&gid, "agg S1: не Stage1".into());
    };

    // lab round 2 (обе группы)
    let r2 = |g: &Vec<f64>, d: &Stage1Decision| {
        prove_with(
            LAB_ELF,
            LAB_ID,
            &LabInput::Round2 { sample: RawSample { values: g.clone() }, decision: *d },
            &[],
        )
    };

    let (lab_output1r2, lab_receipt1r2) = match r2(g1, &decision) {
        Ok((o, s, r)) => {
            add_stat(&mut wall, &mut cyc, &mut usr, &mut seg, &s);
            (o, r)
        }
        Err(e) => return err_run(&gid, format!("lab R2(1): {e}")),
    };
    let LabOutput::Round2(lab1r2) = lab_output1r2 else {
        return err_run(&gid, "lab R2(1): не Round2".into());
    };

    let (lab_output2r2, lab_receipt2r2) = match r2(g2, &decision) {
        Ok((o, s, r)) => {
            add_stat(&mut wall, &mut cyc, &mut usr, &mut seg, &s);
            (o, r)
        }
        Err(e) => return err_run(&gid, format!("lab R2(2): {e}")),
    };
    let LabOutput::Round2(lab2r2) = lab_output2r2 else {
        return err_run(&gid, "lab R2(2): не Round2".into());
    };

    // aggregator stage 2 — итог (тоже композиция)
    let agg2 = match prove_with(
        AGGREGATOR_ELF,
        AGGREGATOR_ID,
        &AggInput::Stage2 {
            lab1: lab1r2.clone(),
            lab2: lab2r2.clone(),
            decision,
            lab1_journal: lab_receipt1r2.journal.bytes.clone(),
            lab2_journal: lab_receipt2r2.journal.bytes.clone(),
        },
        &[lab_receipt1r2.clone(), lab_receipt2r2.clone()],
    ) {
        Ok((o, s, _r)) => {
            add_stat(&mut wall, &mut cyc, &mut usr, &mut seg, &s);
            o
        }
        Err(e) => return err_run(&gid, format!("agg S2: {e}")),
    };
    let AggOutput::Stage2(result) = agg2 else {
        return err_run(&gid, "agg S2: не Stage2".into());
    };

    // ---- сверка с golden ----
    let got_method: f64 = match result.method {
        zkstark_core::Method::Welch => 1.0,
        zkstark_core::Method::Mood => 2.0,
    };
    checks.add_exact("method", got_method, gg("method").unwrap_or(f64::NAN));

    // CPU-эталон для точечных оценок (средние/медианы), не входящих в golden:
    // сверяем их между собой только когда обе группы нормальны (иначе analyze
    // вернёт Err, и критерии с точечными оценками всё равно не сравнить).
    let cpu = analyze(g1, g2, alpha).ok();

    checks.add("sw1.w", result.sw1.w, gg("sw1.w").unwrap());
    checks.add("sw1.p", result.sw1.p_value, gg("sw1.p").unwrap());
    checks.add("sw2.w", result.sw2.w, gg("sw2.w").unwrap());
    checks.add("sw2.p", result.sw2.p_value, gg("sw2.p").unwrap());
    if let Some(exp) = gg("median1") {
        checks.add("median1", lab1.median, exp);
    }
    if let Some(exp) = gg("median2") {
        checks.add("median2", lab2.median, exp);
    }

    let method = Some(match result.method {
        zkstark_core::Method::Welch => MethodOutcome::Welch,
        zkstark_core::Method::Mood => MethodOutcome::Mood,
    });
    match result.method {
        zkstark_core::Method::Welch => {
            if let Some(w) = &result.welch {
                checks.add("welch.t", w.t, gg("welch.t").unwrap());
                checks.add("welch.df", w.df, gg("welch.df").unwrap());
                checks.add("welch.p", w.p_value, gg("welch.p").unwrap());
                // средние групп — golden не содержит; сверяем zk vs CPU analyze()
                if let Some(cp) = cpu.as_ref().and_then(|p| p.welch.as_ref()) {
                    checks.add("welch.mean1", w.mean1, cp.mean1);
                    checks.add("welch.sd1", w.sd1, cp.sd1);
                    checks.add("welch.mean2", w.mean2, cp.mean2);
                    checks.add("welch.sd2", w.sd2, cp.sd2);
                }
            }
        }
        zkstark_core::Method::Mood => {
            if let Some(mr) = &result.median {
                checks.add("m_hat", mr.m_hat, gg("m_hat").unwrap());
                checks.add_exact("mood.a", mr.a as f64, gg("mood.approx.a").unwrap());
                checks.add_exact("mood.b", mr.b as f64, gg("mood.approx.b").unwrap());
                checks.add("mood.p", mr.p_value, gg("mood.approx.p").unwrap());
                // медианы групп — из golden (median1/median2)
                checks.add("median1", mr.median1, gg("median1").unwrap());
                checks.add("median2", mr.median2, gg("median2").unwrap());
            }
        }
    }

    let pass = checks.max <= tol;
    CaseRun {
        scenario: gid,
        status: "ok".into(),
        error_msg: None,
        method,
        checks: checks.list,
        prove_wall_ms: wall,
        total_cycles: cyc,
        user_cycles: usr,
        segments: seg,
        max_rel_err: checks.max,
        pass,
    }
}

/// Прогон всех сценариев с предварительной проверкой на «ожидаемые ошибки».
pub fn run_all(scenarios: &[Scenario], golden: &GoldenValues, tol: f64) -> Vec<CaseRun> {
    scenarios
        .iter()
        .map(|sc| {
            let e1 = zkstark_core::shapiro_wilk(&sc.group1);
            let e2 = zkstark_core::shapiro_wilk(&sc.group2);
            if e1.is_err() || e2.is_err() {
                let msg = match (e1.err(), e2.err()) {
                    (Some(a), _) => a.to_string(),
                    (_, Some(b)) => b.to_string(),
                    _ => String::new(),
                };
                CaseRun {
                    scenario: sc.id.clone(),
                    status: "expected_error".into(),
                    error_msg: Some(msg),
                    method: None,
                    checks: vec![],
                    prove_wall_ms: 0,
                    total_cycles: 0,
                    user_cycles: 0,
                    segments: 0,
                    max_rel_err: 0.0,
                    pass: true,
                }
            } else {
                run_case(sc, golden, tol)
            }
        })
        .collect()
}