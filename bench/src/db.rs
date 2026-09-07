//! SQLite-персистентность результатов прогонов (results/zkstark.db).
//!
//! Схема:
//!   scenarios    — описания сценариев (фиксированы golden.R);
//!   runs         — один прогон bench (режим, время, git-коммит);
//!   case_runs    — результат прогона каждого сценария со всеми метриками;
//!   assertion_errors — отличия zk-значений от golden (по метрикам).

use rusqlite::{params, Connection};
use std::error::Error;

#[derive(Debug)]
pub struct CaseRunRow {
    pub scenario: String,
    pub status: String,
    pub method: Option<String>,
    pub sw1_w: Option<f64>,
    pub sw1_p: Option<f64>,
    pub sw2_w: Option<f64>,
    pub sw2_p: Option<f64>,
    pub welch_t: Option<f64>,
    pub welch_df: Option<f64>,
    pub welch_p: Option<f64>,
    pub welch_mean1: Option<f64>,
    pub welch_mean2: Option<f64>,
    pub welch_sd1: Option<f64>,
    pub welch_sd2: Option<f64>,
    pub m_hat: Option<f64>,
    pub median1: Option<f64>,
    pub median2: Option<f64>,
    pub mood_a: Option<u64>,
    pub mood_b: Option<u64>,
    pub mood_p: Option<f64>,
    pub total_cycles: u64,
    pub user_cycles: u64,
    pub segments: u64,
    pub wall_ms: u64,
    pub asserts: u64,
    pub max_rel_err: Option<f64>,
    pub pass: bool,
    pub error_msg: Option<String>,
}

pub struct Db {
    conn: Connection,
}

impl Db {
    pub fn open(path: &str) -> Result<Self, Box<dyn Error>> {
        let conn = Connection::open(path)?;
        conn.execute_batch(
            "PRAGMA journal_mode=WAL;
             CREATE TABLE IF NOT EXISTS scenarios(
                 cid TEXT PRIMARY KEY, name TEXT, alpha REAL, n1 INTEGER, n2 INTEGER
             );
             CREATE TABLE IF NOT EXISTS runs(
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 run_at TEXT, mode TEXT, git_commit TEXT
             );
             CREATE TABLE IF NOT EXISTS case_runs(
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 run_id INTEGER REFERENCES runs(id),
                 scenario TEXT, status TEXT, method TEXT,
                 sw1_w REAL, sw1_p REAL, sw2_w REAL, sw2_p REAL,
                 welch_t REAL, welch_df REAL, welch_p REAL,
                 welch_mean1 REAL, welch_mean2 REAL, welch_sd1 REAL, welch_sd2 REAL,
                 m_hat REAL, median1 REAL, median2 REAL,
                 mood_a INTEGER, mood_b INTEGER, mood_p REAL,
                 total_cycles INTEGER, user_cycles INTEGER, segments INTEGER,
                 wall_ms INTEGER, asserts INTEGER, max_rel_err REAL,
                 pass INTEGER, error_msg TEXT
             );
             CREATE TABLE IF NOT EXISTS assertion_errors(
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 case_run_id INTEGER, metric TEXT,
                 r_value REAL, zk_value REAL, rel_err REAL
             );",
        )?;
        Ok(Self { conn })
    }

    pub fn upsert_scenario(
        &self,
        case: &str,
        name: &str,
        alpha: f64,
        n1: usize,
        n2: usize,
    ) -> Result<(), Box<dyn Error>> {
        self.conn.execute(
            "INSERT OR REPLACE INTO scenarios(cid, name, alpha, n1, n2)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![case, name, alpha, n1 as i64, n2 as i64],
        )?;
        Ok(())
    }

    pub fn begin_run(&self, now: &str, mode: &str, git: &str) -> Result<i64, Box<dyn Error>> {
        self.conn.execute(
            "INSERT INTO runs(run_at, mode, git_commit) VALUES (?1, ?2, ?3)",
            params![now, mode, git],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn insert_case_run(
        &self,
        run_id: i64,
        r: &CaseRunRow,
    ) -> Result<i64, Box<dyn Error>> {
        self.conn.execute(
            "INSERT INTO case_runs(run_id, scenario, status, method,
                 sw1_w, sw1_p, sw2_w, sw2_p, welch_t, welch_df, welch_p,
                 welch_mean1, welch_mean2, welch_sd1, welch_sd2,
                 m_hat, median1, median2, mood_a, mood_b, mood_p,
                 total_cycles, user_cycles, segments, wall_ms, asserts, max_rel_err,
                 pass, error_msg)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25,?26,?27,?28,?29)",
            params![
                run_id, r.scenario, r.status, r.method,
                r.sw1_w, r.sw1_p, r.sw2_w, r.sw2_p, r.welch_t, r.welch_df, r.welch_p,
                r.welch_mean1, r.welch_mean2, r.welch_sd1, r.welch_sd2,
                r.m_hat, r.median1, r.median2,
                r.mood_a.map(|v| v as i64), r.mood_b.map(|v| v as i64), r.mood_p,
                r.total_cycles as i64, r.user_cycles as i64, r.segments as i64,
                r.wall_ms as i64, r.asserts as i64, r.max_rel_err,
                r.pass as i64, r.error_msg
            ],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn insert_assertion_error(
        &self,
        case_run_id: i64,
        metric: &str,
        r: f64,
        z: f64,
        rel: f64,
    ) -> Result<(), Box<dyn Error>> {
        self.conn.execute(
            "INSERT INTO assertion_errors(case_run_id, metric, r_value, zk_value, rel_err)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![case_run_id, metric, r, z, rel],
        )?;
        Ok(())
    }
}