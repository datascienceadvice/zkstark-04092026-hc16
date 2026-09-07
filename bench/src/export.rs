//! Экспорт результатов прогона в CSV (для анализа в R / статье).

use rusqlite::Connection;
use std::error::Error;

/// Экспортирует прогон run_id в report-строки (по одной на сценарий).
/// Имена файлов: report_<run_id>.csv, errors_<run_id>.csv.
pub fn export_run(conn: &Connection, run_id: i64, dir: &str) -> Result<(), Box<dyn Error>> {
    let cases_out = format!("{dir}/report_{run_id}.csv");
    let errors_out = format!("{dir}/errors_{run_id}.csv");
    let mut stmt = conn.prepare(
        "SELECT c.scenario, c.status, c.method,
                c.sw1_w, c.sw1_p, c.sw2_w, c.sw2_p,
                c.welch_t, c.welch_df, c.welch_p,
                c.welch_mean1, c.welch_mean2, c.welch_sd1, c.welch_sd2,
                c.m_hat, c.median1, c.median2, c.mood_a, c.mood_b, c.mood_p,
                c.total_cycles, c.user_cycles, c.segments, c.wall_ms,
                c.asserts, c.max_rel_err, c.pass, c.error_msg
         FROM case_runs c WHERE c.run_id = ?1
         ORDER BY c.scenario",
    )?;

    let mut w = csv::Writer::from_path(cases_out)?;
    w.write_record(&[
        "case", "status", "method", "sw1_w", "sw1_p", "sw2_w", "sw2_p",
        "welch_t", "welch_df", "welch_p",
        "welch_mean1", "welch_mean2", "welch_sd1", "welch_sd2",
        "m_hat", "median1", "median2", "mood_a", "mood_b", "mood_p",
        "total_cycles", "user_cycles", "segments", "wall_ms",
        "asserts", "max_rel_err", "pass", "error",
    ])?;
    let mut rows = stmt.query([run_id])?;
    while let Some(r) = rows.next()? {
        let f = |i: usize| -> String {
            match r.get_ref(i) {
                Ok(rusqlite::types::ValueRef::Real(v)) => format!("{v:.15e}"),
                Ok(rusqlite::types::ValueRef::Integer(v)) => v.to_string(),
                Ok(rusqlite::types::ValueRef::Text(v)) => String::from_utf8_lossy(v).to_string(),
                _ => "".to_string(),
            }
        };
        w.write_record(&[
            f(0), f(1), f(2), f(3), f(4), f(5), f(6),
            f(7), f(8), f(9), f(10), f(11), f(12), f(13),
            f(14), f(15), f(16), f(17), f(18),
            f(19), f(20), f(21), f(22), f(23),
            f(24), f(25), f(26), f(27),
        ])?;
    }
    w.flush()?;

    let mut stmt2 = conn.prepare(
        "SELECT c.scenario, e.metric, e.r_value, e.zk_value, e.rel_err
         FROM assertion_errors e JOIN case_runs c ON c.id = e.case_run_id
         WHERE c.run_id = ?1 ORDER BY c.scenario, e.metric",
    )?;
    let mut w2 = csv::Writer::from_path(errors_out)?;
    w2.write_record(&["case", "metric", "r_value", "zk_value", "rel_err"])?;
    let mut rows2 = stmt2.query([run_id])?;
    while let Some(r) = rows2.next()? {
        let f = |i: usize| -> String {
            match r.get_ref(i) {
                Ok(rusqlite::types::ValueRef::Real(v)) => format!("{v:.15e}"),
                Ok(rusqlite::types::ValueRef::Integer(v)) => v.to_string(),
                Ok(rusqlite::types::ValueRef::Text(v)) => String::from_utf8_lossy(v).to_string(),
                _ => "".to_string(),
            }
        };
        w2.write_record(&[f(0), f(1), f(2), f(3), f(4)])?;
    }
    w2.flush()?;
    Ok(())
}