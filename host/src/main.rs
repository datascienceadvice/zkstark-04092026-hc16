//! Хост-демонстрация полного zk-протокола сравнения двух лабораторий.
//!
//! Двухраундовая схема с композицией доказательств Risc Zero:
//!   lab R1 (группа 1) → lab R1 (группа 2) → agg S1 →
//!   lab R2 (группа 1) → lab R2 (группа 2) → agg S2
//!
//! Каждый receipt доказывается prover'ом и верифицируется снаружи по method_id;
//! агрегатор дополнительно проверяет журналы лабораторных receipts внутри себя
//! через env::verify (композиция). Показываем итоговый PipelineResult и сверяем
//! его с CPU-версией core::analyze на тех же данных.
//!
//! Запуск (в WSL):  cargo run -p host --release

use methods::{AGGREGATOR_ELF, AGGREGATOR_ID, LAB_ELF, LAB_ID};
use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};
use serde::Serialize;
use std::time::Instant;
use zkstark_core::{
    analyze, AggInput, AggOutput, LabInput, LabOutput, PipelineResult, RawSample,
};

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::filter::EnvFilter::from_default_env())
        .init();

    assert_eq!(
        LAB_ID,
        zkstark_core::LAB_ID_DIGEST,
        "рассинхрон method-id: methods::LAB_ID={LAB_ID:?} vs core::{:?}",
        zkstark_core::LAB_ID_DIGEST,
    );
    // Демо на dev-прототипе: fake receipts (как bench --mode dev), быстрый prover.
    // Для настоящих STARK-доказательств использовать bench --mode full.
    std::env::set_var("RISC0_DEV_MODE", "1");
    eprintln!("host: lab_id={LAB_ID:08x?} agg_id={AGGREGATOR_ID:08x?}");

    // Реалистичные данные двух лабораторий (set.seed(42) из R, golden-тест core).
    let g1 = RawSample {
        values: vec![
            113.709584471467, 94.3530182860391, 103.631284113373, 106.32862604961,
            104.04268323141, 98.9387548390852, 115.115219974389, 99.053409615869,
            120.18423713877, 99.3728590094758, 113.048696542235, 122.866453927011,
            86.1113929888766, 97.2121123318263, 98.6667866360634, 106.359503980701,
            97.1574707858393, 73.4354457909522, 75.5953307142448, 113.201133457302,
            96.9336140592153, 82.1869156602, 98.2808264424038, 112.146746991726,
            118.95193461265, 95.695308683938, 97.4273061723107, 82.3683691480522,
            104.600973548313, 93.6000512403988,
        ],
    };
    let g2 = RawSample {
        values: vec![
            110.465401478895, 113.458048046746, 117.421242263639, 97.6928834951135,
            111.059461479576, 84.3958958511199, 95.586491899446, 94.7891088698818,
            76.0295082006404, 105.433471282707, 107.471983202403, 100.667312417416,
            114.097958828394, 96.2795420750811, 88.5806274669685, 110.193816310665,
            95.2632818857599, 122.329215140655, 99.8226455686399, 112.867774600826,
            108.863103182447, 95.5939327094355, 123.908730237504, 112.714791668608,
            106.077127759195,
        ],
    };
    let alpha = 0.05;
    let prover = default_prover();

    let t0 = Instant::now();

    // ---- Лаборатории, раунд 1 ---------------------------------------------
    let (lab1, receipt1) = prove(
        &prover,
        LAB_ELF,
        LAB_ID,
        &LabInput::Round1(g1.clone()),
        &[],
    );
    let LabOutput::Round1(lab1) = lab1 else { panic!("lab R1(1): не Round1") };

    let (lab2, receipt2) = prove(
        &prover,
        LAB_ELF,
        LAB_ID,
        &LabInput::Round1(g2.clone()),
        &[],
    );
    let LabOutput::Round1(lab2) = lab2 else { panic!("lab R1(2): не Round1") };

    // ---- Агрегатор, раунд 1 (композиция: env::verify внутри гостя) --------
    let decision = match prove(
        &prover,
        AGGREGATOR_ELF,
        AGGREGATOR_ID,
        &AggInput::Stage1 {
            lab1: lab1.clone(),
            lab2: lab2.clone(),
            alpha,
            lab1_journal: receipt1.journal.bytes.clone(),
            lab2_journal: receipt2.journal.bytes.clone(),
        },
        &[receipt1.clone(), receipt2.clone()],
    ) {
        (AggOutput::Stage1(d), _) => d,
        _ => panic!("agg S1: не Stage1"),
    };
    println!("Раунд 1: критерий {:?}, alpha = {alpha}", decision.method);
    if let Some(m) = decision.m_hat {
        println!("  (Mood) M̂ = {m:.9}");
    }

    // ---- Лаборатории, раунд 2 ---------------------------------------------
    let (r2_out1, receipt1r2) = prove::<LabOutput>(
        &prover,
        LAB_ELF,
        LAB_ID,
        &LabInput::Round2 {
            sample: g1.clone(),
            decision,
        },
        &[],
    );
    let LabOutput::Round2(r2_1) = r2_out1 else { panic!("lab R2(1): не Round2") };

    let (r2_out2, receipt2r2) = prove::<LabOutput>(
        &prover,
        LAB_ELF,
        LAB_ID,
        &LabInput::Round2 {
            sample: g2.clone(),
            decision,
        },
        &[],
    );
    let LabOutput::Round2(r2_2) = r2_out2 else { panic!("lab R2(2): не Round2") };

    // ---- Агрегатор, раунд 2 (итог, тоже композиция) ------------------------
    let result = match prove(
        &prover,
        AGGREGATOR_ELF,
        AGGREGATOR_ID,
        &AggInput::Stage2 {
            lab1: r2_1,
            lab2: r2_2,
            decision,
            lab1_journal: receipt1r2.journal.bytes.clone(),
            lab2_journal: receipt2r2.journal.bytes.clone(),
        },
        &[receipt1r2.clone(), receipt2r2.clone()],
    ) {
        (AggOutput::Stage2(r), _) => r,
        _ => panic!("agg S2: не Stage2"),
    };

    println!("Время доказывания: {:.2} c", t0.elapsed().as_secs_f64());

    // ---- Результат и сверка с CPU-версией ----------------------------------
    let cpu = analyze(&g1.values, &g2.values, alpha).expect("данные демо валидны");
    print_result(&result, &cpu);
}

/// Доказать elf с input и предположениями, верифицировать снаружи, декодировать
/// журнал (композиция Risc Zero: assumption'ы разрешают env::verify агрегатора).
fn prove<T>(
    prover: &std::rc::Rc<dyn risc0_zkvm::Prover>,
    elf: &[u8],
    method_id: [u32; 8],
    input: &impl Serialize,
    assumptions: &[Receipt],
) -> (T, Receipt)
where
    T: serde::de::DeserializeOwned,
{
    let mut builder = ExecutorEnv::builder();
    builder.write(input).expect("write input");
    for r in assumptions {
        builder.add_assumption(r.clone());
    }
    let env = builder.build().expect("build env");
    let info = prover.prove(env, elf).expect("prove");
    info.receipt.verify(method_id).expect("verify receipt");
    let out: T = info.receipt.journal.decode().expect("decode journal");
    (out, info.receipt)
}

fn print_result(zk: &PipelineResult, cpu: &PipelineResult) {
    println!("--- Итоговый результат (zk = CPU-эталон) ---");
    println!("метод: {:?} (= {:?})", zk.method, cpu.method);
    println!(
        "Шапиро–Уилк: W1={:.9} p1={:.6} | W2={:.9} p2={:.6}",
        zk.sw1.w,
        zk.sw1.p_value,
        zk.sw2.w,
        zk.sw2.p_value
    );
    match (&zk.welch, &cpu.welch) {
        (Some(w), Some(e)) => {
            println!("Уэлча: t={:.9} df={:.9} p={:.6}", w.t, w.df, w.p_value);
            println!("  (эталон: t={:.9} df={:.9} p={:.6})", e.t, e.df, e.p_value);
        }
        _ => println!("(критерий Уэлча не выбран)"),
    }
    match (&zk.median, &cpu.median) {
        (Some(m), Some(e)) => {
            println!(
                "Муд: M̂={:.9} a={} b={} p={:.6}",
                m.m_hat, m.a, m.b, m.p_value
            );
            println!("  (эталон: a={} b={} p={:.6})", e.a, e.b, e.p_value);
        }
        _ => println!("(критерий Муда не выбран)"),
    }
}