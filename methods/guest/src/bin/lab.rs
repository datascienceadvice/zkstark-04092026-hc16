//! Лаборатория: обработка сырых данных без раскрытия значений.
//!
//! Два раунда протокола:
//! 1. Round1 — сводные статистики + критерий Шапиро–Уилка + медиана группы;
//! 2. Round2 — то же самое + число наблюдений > M̂ (для медианного теста Муда).
//!
//! Commit (journal) публикует только агрегированные метрики. Гость собирается
//! на гостевом std (тулчейн risc0): f64-математика требует std-обёрток
//! (`sqrt`, `powf` и т.п. отсутствуют в core для этого таргета).
use risc0_zkvm::guest::env;

use zkstark_core::{
    count_above, median, shapiro_wilk, summarize, LabInput, LabOutput, RawSample,
};

/// Сводные статистики + Шапиро–Уилк + медиана группы.
///
/// `need_median` выключает сортировку медианы: во втором раунде при выборе
/// Уэлча агрегатору медиана не нужна (она используется только для M̂ при Mood).
fn materialize(sample: &RawSample, need_median: bool) -> zkstark_core::LabResult {
    let stats = summarize(&sample.values);
    let sw = shapiro_wilk(&sample.values).expect("invalid sample");
    let median = if need_median {
        median(&sample.values)
    } else {
        f64::NAN
    };
    zkstark_core::LabResult { stats, sw, median }
}

fn main() {
    let input: LabInput = env::read();
    let output = match input {
        LabInput::Round1(sample) => LabOutput::Round1(materialize(&sample, true)),
        LabInput::Round2 { sample, decision } => {
            let r1 = materialize(&sample, decision.m_hat.is_some());
            let count = decision
                .m_hat
                .map(|m_hat| count_above(&sample.values, m_hat));
            LabOutput::Round2(zkstark_core::LabResultRound2 {
                round1: r1,
                count_above: count,
            })
        }
    };
    env::commit(&output);
}