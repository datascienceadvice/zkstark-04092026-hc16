use methods::{AGGREGATOR_ELF, AGGREGATOR_ID, LAB_ELF, LAB_ID};
use risc0_zkvm::{default_prover, ExecutorEnv};
use zkstark_core::{RawSample, SummaryStats, WelchResult};

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::filter::EnvFilter::from_default_env())
        .init();

    // Реалистичные данные двух лабораторий (set.seed(42) из R, golden-тест core).
    let lab1 = RawSample {
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
    let lab2 = RawSample {
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

    let prover = default_prover();
    println!("Lab1: {} образцов", lab1.values.len());
    println!("Lab2: {} образцов", lab2.values.len());

    // --- Лаборатория 1 ---
    let env1 = ExecutorEnv::builder().write(&lab1).unwrap().build().unwrap();
    let prove1 = prover.prove(env1, LAB_ELF).unwrap();
    let receipt1 = prove1.receipt;
    let summary1: SummaryStats = receipt1.journal.decode().unwrap();
    receipt1.verify(LAB_ID).unwrap();
    println!("Lab1 summary: {:?}", summary1);

    // --- Лаборатория 2 ---
    let env2 = ExecutorEnv::builder().write(&lab2).unwrap().build().unwrap();
    let prove2 = prover.prove(env2, LAB_ELF).unwrap();
    let receipt2 = prove2.receipt;
    let summary2: SummaryStats = receipt2.journal.decode().unwrap();
    receipt2.verify(LAB_ID).unwrap();
    println!("Lab2 summary: {:?}", summary2);

    // --- Агрегатор ---
    let input = (summary1, summary2);
    let env3 = ExecutorEnv::builder().write(&input).unwrap().build().unwrap();
    let prove3 = prover.prove(env3, AGGREGATOR_ELF).unwrap();
    let receipt3 = prove3.receipt;
    let result: WelchResult = receipt3.journal.decode().unwrap();
    receipt3.verify(AGGREGATOR_ID).unwrap();

    println!("--- Welch t-test ---");
    println!("mean1 = {:.6}, sd1 = {:.6}", result.mean1, result.sd1);
    println!("mean2 = {:.6}, sd2 = {:.6}", result.mean2, result.sd2);
    println!("t     = {:.9} (R: -1.026509359955)", result.t);
    println!("df    = {:.9} (R: 52.333972848482)", result.df);
    println!("p     = {:.9} (R: 0.309372915729)", result.p_value);
}