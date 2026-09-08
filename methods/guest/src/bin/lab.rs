//! Лаборатория: обработка сырых данных без раскрытия значений.
//!
//! Два раунда протокола:
//! 1. Round1 — сводные статистики + критерий Шапиро–Уилка + медиана
//!    и квартили Q1/Q3 группы;
//! 2. Round2 — то же самое + число наблюдений > M̂ (для медианного теста Муда).
//!
//! Commit (journal) публикует только агрегированные метрики. Гость собирается
//! на гостевом std (тулчейн risc0): f64-математика требует std-обёрток
//! (`sqrt`, `powf` и т.п. отсутствуют в core для этого таргета).
use risc0_zkvm::guest::env;

use zkstark_core::{
    count_above, median, quartiles, shapiro_wilk, summarize, LabInput, LabOutput, RawSample,
};

/// Сводные статистики + Шапиро–Уилк + медиана и квартили группы.
///
/// `need_median` выключает сортировку медианы/квартилей: во втором раунде
/// при выборе Уэлча агрегатору они не нужны (используются только для M̂ при
/// Mood).
fn materialize(sample: &RawSample, need_median: bool) -> zkstark_core::LabResult {
    let stats = summarize(&sample.values);
    let sw = shapiro_wilk(&sample.values).expect("invalid sample");
    let (median, q1, q3) = if need_median {
        let m = median(&sample.values);
        let (l, u) = quartiles(&sample.values);
        (m, l, u)
    } else {
        (f64::NAN, f64::NAN, f64::NAN)
    };
    zkstark_core::LabResult { stats, sw, median, q1, q3 }
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