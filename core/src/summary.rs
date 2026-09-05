//! Сводные статистики и описательная статистика.

/// Сводные статистики группы — всё, что нужно агрегатору от лаборатории.
///
/// Достаточно N, суммы и суммы квадратов, чтобы вычислить среднее и
/// несмещённую дисперсию (и, далее, Уэлча t-тест), не раскрывая сырые данные.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, Copy, PartialEq)]
pub struct SummaryStats {
    pub n: usize,
    pub sum: f64,
    pub sum_sq: f64,
}

impl SummaryStats {
    pub const fn new(n: usize, sum: f64, sum_sq: f64) -> Self {
        Self { n, sum, sum_sq }
    }

    /// Описательная статистика по сводным.
    pub fn describe(&self) -> DescriptiveStats {
        describe(self)
    }

    /// Несмещённая выборочная дисперсия (n-1 знаменатель).
    pub fn variance(&self) -> f64 {
        if self.n < 2 {
            return f64::NAN;
        }
        let n = self.n as f64;
        (self.sum_sq - self.sum * self.sum / n) / (n - 1.0)
    }
}

/// Описательная статистика одной группы.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, Copy, PartialEq)]
pub struct DescriptiveStats {
    pub n: usize,
    pub mean: f64,
    pub sd: f64, // выборочное СКО (несмещ., n-1)
}

/// Вычислить описательную статистику из сводных.
pub fn describe(s: &SummaryStats) -> DescriptiveStats {
    let n = s.n;
    if n == 0 {
        return DescriptiveStats { n: 0, mean: f64::NAN, sd: f64::NAN };
    }
    let mean = s.sum / n as f64;
    let sd = if n < 2 { f64::NAN } else { s.variance().sqrt() };
    DescriptiveStats { n, mean, sd }
}

/// Построить сводные статистики из сырых значений (используется на стороне
/// лаборатории; те же числа, что даёт R `mean`/`sd`).
pub fn summarize(values: &[f64]) -> SummaryStats {
    let n = values.len();
    let mut sum = 0.0;
    let mut sum_sq = 0.0;
    for &v in values {
        sum += v;
        sum_sq += v * v;
    }
    SummaryStats { n, sum, sum_sq }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summarizes_correctly() {
        let x = [1.0, 2.0, 3.0, 4.0, 5.0];
        let s = summarize(&x);
        assert_eq!(s.n, 5);
        assert!((s.sum - 15.0).abs() < 1e-12);
        assert!((s.sum_sq - 55.0).abs() < 1e-12);
        let d = s.describe();
        assert!((d.mean - 3.0).abs() < 1e-12);
        // sd(x) в R для c(1..5) = sqrt(var), var=2.5
        assert!((d.sd - 2.5_f64.sqrt()).abs() < 1e-12);
    }

    #[test]
    fn single_sample_has_nan_sd() {
        let s = summarize(&[7.0]);
        assert!(s.describe().sd.is_nan());
        assert!((s.describe().mean - 7.0).abs() < 1e-12);
    }
}
