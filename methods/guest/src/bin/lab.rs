use risc0_zkvm::guest::env;
use zkstark_core::{summarize, RawSample};

fn main() {
    // Лаборатория получает сырые данные, считает сводные статистики
    // (n, sum, sum_sq) и публикует их в journal. Сырые значения не раскрываются.
    let sample: RawSample = env::read();
    let summary = summarize(&sample.values);
    env::commit(&summary);
}