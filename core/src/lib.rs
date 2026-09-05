//! Статистическое ядро zkstark (MVP).
//!
//! Реализует описательную статистику и Уэлча t-тест из сводных статистик,
//! достаточных для работы в Risc Zero zkVM. Типы сериализуются через serde
//! и используются как вход (env::read) и выход (env::commit → journal) гостевых
//! программ. Численная реализация — без внешних стат-крейтов.
#![deny(unsafe_code)]

pub mod special; // специальные функции: ln_gamma, неполная бета, t-CDF
pub mod summary; // среднее, СКО, сводные статистики
pub mod welch; // Уэлча t-тест

use serde::{Deserialize, Serialize};

pub use summary::{summarize, DescriptiveStats, SummaryStats};
pub use welch::WelchResult;

/// Сырая выборка — вход гостевой программы лаборатории.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct RawSample {
    pub values: Vec<f64>,
}

/// Двусторонний Уэлча t-тест по сводным статистикам двух групп.
pub fn welch_from_summary(a: &SummaryStats, b: &SummaryStats) -> WelchResult {
    welch::welch(a, b)
}