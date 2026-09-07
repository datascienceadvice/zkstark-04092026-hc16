//! Статистическое ядро zkstark.
//!
//! Реализует двухвыборочный протокол с автоматическим выбором критерия:
//! 1) нормальность каждой группы — критерий Шапиро–Уилка (как R `shapiro.test`);
//! 2) если обе нормальны (p > α) — Уэлча t-тест, иначе — медианный тест Муда
//!    с точным p-уровнем Фишера 2×2.
//!
//! Численная реализация — без внешних стат-крейтов, заточенная под Risc Zero
//! zkVM (no_std, без f64::log1p и прочих отсутствующих в гостевой std операций).
//! Все типы сериализуются через serde и передаются между гостевыми программами
//! (лаборатория ↔ агрегатор).
#![deny(unsafe_code)]

pub mod mood; // медианный тест Муда + точный Фишер 2×2
pub mod shapiro; // критерий Шапиро–Уилка (порт R swilk)
pub mod special; // специальные функции: гамма, бета, t-CDF, норма
pub mod summary; // среднее, СКО, сводные статистики
pub mod welch; // Уэлча t-тест

use serde::{Deserialize, Serialize};

pub use mood::{count_above, fisher_two_sided_2x2, median, mood_median_test, MedianTestResult};
pub use shapiro::{shapiro_wilk, ShapiroResult};
pub use summary::{summarize, DescriptiveStats, SummaryStats};
pub use welch::{welch, WelchResult};

/// Сырая выборка — вход гостевой программы лаборатории.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct RawSample {
    pub values: Vec<f64>,
}

/// Двусторонний Уэлча t-тест по сводным статистикам двух групп.
pub fn welch_from_summary(a: &SummaryStats, b: &SummaryStats) -> WelchResult {
    welch::welch(a, b)
}

/// Выбранный критерий сравнения групп.
#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
pub enum Method {
    /// Обе группы признаны нормальными — применяем Уэлча t-тест
    #[serde(rename = "welch")]
    Welch,
    /// Хотя бы одна группа не нормальна — применяем медианный тест Муда
    #[serde(rename = "mood")]
    Mood,
}

/// Результат первого (подготовительного) раунда лаборатории.
///
/// Присылается агрегатору до начала сравнения: сводные статистики для
/// Уэлча, результат Шапиро–Уилка и медиана группы (для M̂ агрегатора).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct LabResult {
    pub stats: SummaryStats,
    pub sw: ShapiroResult,
    pub median: f64,
}

/// Решение агрегатора по итогам первого раунда.
///
/// Выбирает критерий (Method) и, если выбран Mood, возвращает оценку общей
/// медианы M̂ = mean(median1, median2), которую лаборатории используют для
/// подсчёта count_above во втором раунде.
#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq)]
pub struct Stage1Decision {
    pub method: Method,
    pub alpha: f64,
    pub m_hat: Option<f64>,
}

/// Результат второго раунда лаборатории: к входным данными первого раунда
/// добавляется count_above(M̂) — заполнено, только если выбран Mood.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct LabResultRound2 {
    pub round1: LabResult,
    pub count_above: Option<usize>,
}

/// Итоговый результат протокола сравнения двух групп.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct PipelineResult {
    pub method: Method,
    pub alpha: f64,
    pub sw1: ShapiroResult,
    pub sw2: ShapiroResult,
    pub welch: Option<WelchResult>,
    pub median: Option<MedianTestResult>,
}

/// Первый раунд агрегатора: выбрать критерий и (при Mood) найти M̂.
pub fn stage1(lab1: &LabResult, lab2: &LabResult, alpha: f64) -> Stage1Decision {
    let both_normal = lab1.sw.p_value > alpha && lab2.sw.p_value > alpha;
    if both_normal {
        Stage1Decision {
            method: Method::Welch,
            alpha,
            m_hat: None,
        }
    } else {
        Stage1Decision {
            method: Method::Mood,
            alpha,
            m_hat: Some(0.5 * (lab1.median + lab2.median)),
        }
    }
}

/// Второй (заключительный) раунд агрегатора: итоговый результат сравнения.
pub fn stage2(
    lab1: &LabResultRound2,
    lab2: &LabResultRound2,
    decision: &Stage1Decision,
) -> PipelineResult {
    match decision.method {
        Method::Welch => PipelineResult {
            method: Method::Welch,
            alpha: decision.alpha,
            sw1: lab1.round1.sw,
            sw2: lab2.round1.sw,
            welch: Some(welch_from_summary(&lab1.round1.stats, &lab2.round1.stats)),
            median: None,
        },
        Method::Mood => PipelineResult {
            method: Method::Mood,
            alpha: decision.alpha,
            sw1: lab1.round1.sw,
            sw2: lab2.round1.sw,
            welch: None,
            median: Some(finish_mood(lab1, lab2, decision)),
        },
    }
}

/// Завершение медманного теста по count_above из второго раунда.
fn finish_mood(lab1: &LabResultRound2, lab2: &LabResultRound2, decision: &Stage1Decision) -> MedianTestResult {
    let a = lab1.count_above.unwrap_or(0);
    let b = lab2.count_above.unwrap_or(0);
    let nx = lab1.round1.stats.n;
    let ny = lab2.round1.stats.n;
    MedianTestResult {
        m_hat: decision.m_hat.unwrap_or(f64::NAN),
        median1: lab1.round1.median,
        median2: lab2.round1.median,
        a,
        b,
        p_value: fisher_two_sided_2x2(a, nx, b, ny),
    }
}

/// Полный протокол «лаборатория → агрегатор → лабортория → агрегатор» по
/// сырым выборкам без зk-части: удобно для проверок и симуляций.
///
/// Возвращает `Err`, если хотя бы одна выборка недопустима для Шапиро–Уилка
/// (например, константная группа — там критерий Муда всё равно теряет смысл).
pub fn analyze(x: &[f64], y: &[f64], alpha: f64) -> Result<PipelineResult, String> {
    let sw1 = shapiro_wilk(x).map_err(|e| format!("invalid first sample: {e}"))?;
    let sw2 = shapiro_wilk(y).map_err(|e| format!("invalid second sample: {e}"))?;
    let lab1 = LabResult {
        stats: summarize(x),
        sw: sw1,
        median: median(x),
    };
    let lab2 = LabResult {
        stats: summarize(y),
        sw: sw2,
        median: median(y),
    };
    let decision = stage1(&lab1, &lab2, alpha);
    let lab1r2 = LabResultRound2 {
        round1: lab1,
        count_above: decision.m_hat.map(|m| count_above(x, m)),
    };
    let lab2r2 = LabResultRound2 {
        round1: lab2,
        count_above: decision.m_hat.map(|m| count_above(y, m)),
    };
    Ok(stage2(&lab1r2, &lab2r2, &decision))
}

// ---------------------------------------------------------------------------
// Входные/выходные типы гостевых программ (используют те же сериализации).
// ---------------------------------------------------------------------------

/// Вход лаборатории: первый раунд (сырые данные) или второй раунд
/// (сырые данные + решение агрегатора с M̂).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum LabInput {
    /// Первый раунд: данные без внешней информации
    Round1(RawSample),
    /// Второй раунд: данные и решение агрегатора (для count_above при Mood)
    Round2 {
        sample: RawSample,
        decision: Stage1Decision,
    },
}

/// Выход лаборатории: результат первого или второго раунда.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum LabOutput {
    Round1(LabResult),
    Round2(LabResultRound2),
}

/// Вход агрегатора: первый (S1) или заключительный (S2) раунд.
///
/// Поля `lab1_journal`/`lab2_journal` несут байты журналов соответствующих
/// лабораторных доказательств — агрегатор проверяет их в гостевой среде через
/// `env::verify(LAB_ID, journal)` (композиция доказательств Risc Zero).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum AggInput {
    /// Первый раунд: результаты двух лабораторий + alpha
    Stage1 {
        lab1: LabResult,
        lab2: LabResult,
        alpha: f64,
        #[serde(default)]
        lab1_journal: Vec<u8>,
        #[serde(default)]
        lab2_journal: Vec<u8>,
    },
    /// Заключительный раунд: результаты второго раунда лабораторий + решение
    Stage2 {
        lab1: LabResultRound2,
        lab2: LabResultRound2,
        decision: Stage1Decision,
        #[serde(default)]
        lab1_journal: Vec<u8>,
        #[serde(default)]
        lab2_journal: Vec<u8>,
    },
}

/// Выход агрегатора: решение первого раунда или итоговый результат.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum AggOutput {
    Stage1(Stage1Decision),
    Stage2(PipelineResult),
}

/// Method ID гостевой программы лаборатории — для `env::verify(LAB_ID, journal)`
/// внутри агрегатора (композиция доказательств Risc Zero).
///
/// Значение снимается из `target/release/build/methods-*/out/methods.rs`
/// (LAB_ID) и держится синхронно с гостевой сборкой: после любых правок гостя
/// LAB_ID меняется, и его нужно обновить здесь вручную.
pub const LAB_ID_DIGEST: [u32; 8] = [
    1004439141, 2032882931, 2313745450, 3887501708, 3892065074, 4216237220, 4180787024, 2582466225,
];