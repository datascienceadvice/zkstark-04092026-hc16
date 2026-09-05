//! Вспомогательные структуры для bench: сценарий, golden-значения, прогон.

use std::collections::HashMap;

/// Один сценарий из results/scenarios.csv.
#[derive(Debug, Clone)]
pub struct Scenario {
    pub id: String,
    pub name: String,
    pub alpha: f64,
    pub group1: Vec<f64>,
    pub group2: Vec<f64>,
}

/// Golden-значения (results/golden.csv): case -> metric -> value.
pub type GoldenValues = HashMap<String, HashMap<String, f64>>;

/// Результат одной верификационной проверки (метрика против golden).
#[derive(Debug, Clone)]
pub struct Check {
    pub metric: String,
    pub expected: f64,
    pub got: f64,
    pub rel_err: f64,
}

/// Выбранный критерий в итоговом результате протокола.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MethodOutcome {
    Welch,
    Mood,
}

/// Итоги одного запуска одного сценария.
#[derive(Debug)]
pub struct CaseRun {
    pub scenario: String,
    /// ok | expected_error | error
    pub status: String,
    pub error_msg: Option<String>,
    pub method: Option<MethodOutcome>,
    pub checks: Vec<Check>,
    /// Суммарное время (мс) всех доказательств сценария
    pub prove_wall_ms: u64,
    pub total_cycles: u64,
    pub user_cycles: u64,
    pub segments: usize,
    pub max_rel_err: f64,
    pub pass: bool,
}