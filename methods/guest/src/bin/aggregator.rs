use risc0_zkvm::guest::env;
use zkstark_core::{welch_from_summary, SummaryStats};

fn main() {
    // Агрегатор получает по одной сводной статистике от каждой лаборатории
    // и вычисляет Уэлча t-тест (t, df, p) + описательную статистику групп.
    // В MVP верификация proof'ов выполняется на стороне host.
    let (a, b): (SummaryStats, SummaryStats) = env::read();
    let result = welch_from_summary(&a, &b);
    env::commit(&result);
}