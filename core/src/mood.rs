//! Медианный тест Муда (двухвыборочный) с точным p-уровнем Фишера 2×2.
//!
//! Работает по протоколу: лаборатории присваивают медианы и квартили групп,
//! агрегатор вычисляет общую (объединённую) оценку M̂ — взвешенное по
//! объёму и квартильной плотности среднее медиан групп — и возвращает её
//! лабораториям; те, в свою очередь, присылают число наблюдений строго
//! больше M̂ (count_above). По таблице 2×2 агрегатор находит двусторонний
//! p-уровень точно (Irwin–Fisher), как `fisher.test()$p.value`.
//!
//! Мотивация весов: для истинной объединённой медианы m₀ = median(c(x, y))
//! выполняется n₁·P(X ≤ m₀) + n₂·P(Y ≤ m₀) = (n₁+n₂)/2. Линеаризуя CDF групп
//! в окрестности медианы через квартили (dⱼ = 0.5/IQRⱼ), получаем
//! m₀ ≈ (n₁·d₁·med₁ + n₂·d₂·med₂) / (n₁·d₁ + n₂·d₂) — группа с большим
//! объёмом и меньшим разбросом тянет M̂ к себе, как и должно быть.

use crate::special::ln_gamma;

/// Результат медианного теста Муда.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, Copy, PartialEq)]
pub struct MedianTestResult {
    /// Оценка общей медианы: взвешенное по n×IQR-плотности среднее медиан групп
    pub m_hat: f64,
    /// Медиана группы 1
    pub median1: f64,
    /// Медиана группы 2
    pub median2: f64,
    /// Число наблюдений группы 1 строго больше M̂
    pub a: usize,
    /// Число наблюдений группы 2 строго больше M̂
    pub b: usize,
    /// Двусторонний точный p-уровень (fisher.test, two.sided)
    pub p_value: f64,
}

/// Медиана по умолчанию R (`median.default`, тип 7): для чётного n — полусумма
/// двух центральных значений.
pub fn median(values: &[f64]) -> f64 {
    let mut v = values.to_vec();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(core::cmp::Ordering::Equal));
    let n = v.len();
    if n == 0 {
        return f64::NAN;
    }
    let mid = n / 2;
    if n % 2 == 1 {
        v[mid]
    } else {
        0.5 * (v[mid - 1] + v[mid])
    }
}

/// Квартили Q1/Q3 (R `quantile(x, c(.25, .75))`, тип 7).
///
/// Для индекса `1 + (n−1)·p` — линейная интерполяция между соседними
/// порядковыми статистиками, с зажатием в [1, n].
pub fn quartiles(values: &[f64]) -> (f64, f64) {
    let mut v = values.to_vec();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(core::cmp::Ordering::Equal));
    let n = v.len();
    if n == 0 {
        return (f64::NAN, f64::NAN);
    }
    let quantile = |p: f64| {
        let idx = (1.0 + (n as f64 - 1.0) * p).clamp(1.0, n as f64);
        let lo = idx.floor();
        let hi = idx.ceil();
        let ilo = lo as usize - 1;
        let ihi = hi as usize - 1;
        v[ilo] + (idx - lo) * (v[ihi] - v[ilo])
    };
    (quantile(0.25), quantile(0.75))
}

/// Плотностный вес группы: d = 0.5/IQR (линейная аппроксимация CDF в
/// окрестности медианы). При IQR ≤ 0 (вырожденная/дискретная зона) — 0.
fn density_weight(iqr: f64) -> f64 {
    if iqr > 0.0 { 0.5 / iqr } else { 0.0 }
}

/// Квартильно-взвешенная оценка общей медианы m₀ = median(c(x, y)).
///
/// `m = (n₁·d₁·med₁ + n₂·d₂·med₂) / (n₁·d₁ + n₂·d₂)`, где `dⱼ = 0.5/IQRⱼ`.
/// Если обе плотности нулевые (обе группы дискретно-вырожденные) — веса
/// сводятся к объёмам выборок, как для взвешенной медианы.
pub fn mhat_quartile(
    n1: usize, median1: f64, iqr1: f64,
    n2: usize, median2: f64, iqr2: f64,
) -> f64 {
    let w1 = n1 as f64 * density_weight(iqr1);
    let w2 = n2 as f64 * density_weight(iqr2);
    let wsum = w1 + w2;
    if wsum > 0.0 {
        (w1 * median1 + w2 * median2) / wsum
    } else {
        (n1 as f64 * median1 + n2 as f64 * median2) / (n1 as f64 + n2 as f64)
    }
}

/// Количество наблюдений, строго больших `threshold`.
pub fn count_above(values: &[f64], threshold: f64) -> usize {
    values.iter().filter(|&&v| v > threshold).count()
}

fn ln_choose(n: usize, k: usize) -> f64 {
    if k > n {
        return f64::NEG_INFINITY;
    }
    if k == 0 || k == n {
        return 0.0;
    }
    ln_gamma(n as f64 + 1.0) - ln_gamma(k as f64 + 1.0) - ln_gamma((n - k) as f64 + 1.0)
}

/// Точный двусторонний p-уровень для таблицы 2×2
///
/// ```text
///        |  > M̂  |  ≤ M̂  |
///    X   |   a   | nx-a  | nx
///    Y   |   b   | ny-b  | ny
///        | a+b   |       | N
/// ```
///
/// Как в R `fisher.test(alternative = "two.sided")`: суммируются вероятности
/// (гипергеометрическое распределение) всех таблиц не «маловероятнее» наблюдаемой:
/// P(table) <= P(наблюдаемая), в лог-пространстве с малым относительным запасом.
pub fn fisher_two_sided_2x2(a: usize, nx: usize, b: usize, ny: usize) -> f64 {
    let t = a + b; // всего наблюдений выше M̂
    let k_min = t.saturating_sub(ny);
    let k_max = t.min(nx);
    let ln_tot = ln_choose(nx + ny, t);
    let log_p_obs = ln_choose(nx, a) + ln_choose(ny, b) - ln_tot;
    let mut p = 0.0;
    for k in k_min..=k_max {
        let log_pk = ln_choose(nx, k) + ln_choose(ny, t - k) - ln_tot;
        // относительный запас ~1e-12, как guard от округлений в R:
        // prob <= prt * (1 + 1e-7)
        if log_pk <= log_p_obs + 1e-12 {
            p += log_pk.exp();
        }
    }
    p.min(1.0)
}

/// Медианный тест Муда по сырым выборкам (без пересылки через гостей).
///
/// Полезно для симуляций и проверки; в zk-протоколе лаборатории используют
/// только median(), quartiles(), count_above() и медианное решение агрегатора.
pub fn mood_median_test(x: &[f64], y: &[f64]) -> MedianTestResult {
    let median1 = median(x);
    let median2 = median(y);
    let (q1_1, q3_1) = quartiles(x);
    let (q1_2, q3_2) = quartiles(y);
    let m_hat = mhat_quartile(
        x.len(), median1, q3_1 - q1_1,
        y.len(), median2, q3_2 - q1_2,
    );
    let a = count_above(x, m_hat);
    let b = count_above(y, m_hat);
    let p_value = fisher_two_sided_2x2(a, x.len(), b, y.len());
    MedianTestResult { m_hat, median1, median2, a, b, p_value }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn median_matches_r_conventions() {
        assert_eq!(median(&[3.0, 1.0, 2.0]), 2.0);
        assert_eq!(median(&[1.0, 2.0, 3.0, 4.0]), 2.5);
        assert_eq!(median(&[1.0]), 1.0);
        assert!(median(&[]).is_nan());
    }

    #[test]
    fn count_above_counts_strict() {
        assert_eq!(count_above(&[1.0, 2.0, 3.0, 3.0], 3.0), 0);
        assert_eq!(count_above(&[1.0, 2.0, 3.0, 4.0], 3.0), 1);
        assert_eq!(count_above(&[1.0, 2.0, 3.0], 2.0), 1);
    }

    #[test]
    fn fisher_is_symmetric() {
        // Обмен строк меняет местами a и b: p не зависит от порядка групп
        let p1 = fisher_two_sided_2x2(9, 20, 4, 20);
        let p2 = fisher_two_sided_2x2(4, 20, 9, 20);
        assert!((p1 - p2).abs() < 1e-15);
    }

    #[test]
    fn fisher_degenerate_returns_one() {
        // Все значения равны — таблица {0,0}/{0,0}, p=1
        let p = fisher_two_sided_2x2(0, 5, 0, 5);
        assert!((p - 1.0).abs() < 1e-12);
    }

    #[test]
    fn mood_zero_effect_gives_large_p() {
        let x = [1.0, 2.0, 3.0, 4.0, 5.0];
        let y = [1.5, 2.5, 3.5, 4.5, 5.5];
        let r = mood_median_test(&x, &y);
        assert!(r.p_value > 0.05, "p={}", r.p_value);
    }
}