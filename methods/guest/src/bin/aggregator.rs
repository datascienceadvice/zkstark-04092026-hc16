use risc0_zkvm::guest::env;
use zkstark_core::{stage1, stage2, AggInput, AggOutput};

/// Агрегатор: два раунда протокола.
fn main() {
    let input: AggInput = env::read();
    let output = match input {
        AggInput::Stage1 { lab1, lab2, alpha } => AggOutput::Stage1(stage1(&lab1, &lab2, alpha)),
        AggInput::Stage2 {
            lab1,
            lab2,
            decision,
        } => AggOutput::Stage2(stage2(&lab1, &lab2, &decision)),
    };
    env::commit(&output);
}