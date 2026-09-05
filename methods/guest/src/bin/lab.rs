use risc0_zkvm::guest::env;
use zkstark_core::{
    count_above, median, shapiro_wilk, summarize, LabInput, LabOutput, RawSample,
};

/// Лаборатория: обработка сырых данных без раскрытия значений.
///
/// Два раунда протокола:
/// 1. Round1 — сводные статистики + критерий Шапиро–Уилка + медиана группы;
/// 2. Round2 — то же самое + число наблюдений > M̂ (для медианного теста Муда).
///
/// Commit (journal) публикует только агрегированные метрики.
fn round1_materialize(sample: &RawSample) -> zkstark_core::LabResult {
    let stats = summarize(&sample.values);
    let sw = shapiro_wilk(&sample.values).expect("invalid sample");
    let med = median(&sample.values);
    zkstark_core::LabResult {
        stats,
        sw,
        median: med,
    }
}

fn main() {
    let input: LabInput = env::read();
    let output = match input {
        LabInput::Round1(sample) => {
            let r1 = round1_materialize(&sample);
            LabOutput::Round1(r1)
        }
        LabInput::Round2 { sample, decision } => {
            let r1 = round1_materialize(&sample);
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