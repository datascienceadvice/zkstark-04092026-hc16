//! Агрегатор: два раунда протокола.
//!
//! Проверяет лабораторные доказательства прямо внутри гостевой среды через
//! `env::verify(LAB_ID, journal)` — композиция доказательств Risc Zero.
//! Итоговый receipt агрегатора достоверен только если лабораторные receipts
//! верны и их журналы совпадают с байтами, поданными агрегатором.
//! Гость собирается на гостевом std (тулчейн risc0) — по тем же причинам,
//! что и guest/lab.
use risc0_zkvm::guest::env;

use zkstark_core::{stage1, stage2, AggInput, AggOutput, LAB_ID_DIGEST};

fn main() {
    let input: AggInput = env::read();
    let output = match input {
        AggInput::Stage1 {
            lab1,
            lab2,
            alpha,
            lab1_journal,
            lab2_journal,
        } => {
            env::verify(LAB_ID_DIGEST, &lab1_journal).expect("verify lab1 journal");
            env::verify(LAB_ID_DIGEST, &lab2_journal).expect("verify lab2 journal");
            AggOutput::Stage1(stage1(&lab1, &lab2, alpha))
        }
        AggInput::Stage2 {
            lab1,
            lab2,
            decision,
            lab1_journal,
            lab2_journal,
        } => {
            env::verify(LAB_ID_DIGEST, &lab1_journal).expect("verify lab1 journal");
            env::verify(LAB_ID_DIGEST, &lab2_journal).expect("verify lab2 journal");
            AggOutput::Stage2(stage2(&lab1, &lab2, &decision))
        }
    };
    env::commit(&output);
}