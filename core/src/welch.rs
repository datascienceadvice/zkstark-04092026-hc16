//! Уэлча t-тест (независимые выборки, без предположения о равенстве дисперсий).

use crate::special::{t_two_tailed_p};
use crate::summary::{describe, DescriptiveStats, SummaryStats};

/// Результат Уэлча t-теста.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, Copy, PartialEq)]
pub struct WelchResult {
    pub t: f64,
    pub df: f64,
    pub p_value: f64, // двусторонняя p
    pub mean1: f64,
    pub sd1: f64,
    pub mean2: f64,
    pub sd2: f64,
    pub n1: usize,
    pub n2: usize,
}

/// Выполнить Уэлча t-тест по сводным статистикам двух групп.
pub fn welch(a: &SummaryStats, b: &SummaryStats) -> WelchResult {
    let da = describe(a);
    let db = describe(b);
    welch_descriptive(&da, &db)
}

/// Уэлча t-тест по готовой описательной статистике.
pub fn welch_descriptive(a: &DescriptiveStats, b: &DescriptiveStats) -> WelchResult {
    let n1 = a.n as f64;
    let n2 = b.n as f64;
    let var1 = a.sd * a.sd;
    let var2 = b.sd * b.sd;

    // se = sqrt(var1/n1 + var2/n2)
    let se2 = var1 / n1 + var2 / n2;
    if se2 <= 0.0 {
        // обе группы имеют нулевую дисперсию — сравнение вырождено
        let t = if se2 < 0.0 {
            f64::NAN
        } else {
            if a.mean == b.mean {
                0.0
            } else if a.mean > b.mean {
                f64::INFINITY
            } else {
                f64::NEG_INFINITY
            }
        };
        return WelchResult {
            t,
            df: 0.0,
            p_value: 0.0,
            mean1: a.mean,
            sd1: a.sd,
            mean2: b.mean,
            sd2: b.sd,
            n1: a.n,
            n2: b.n,
        };
    }

    let se = se2.sqrt();
    let t = (a.mean - b.mean) / se;

    // Статистика Саттертуэйта для числа степеней свободы.
    let df = if var1 == 0.0 && var2 == 0.0 {
        f64::NAN
    } else {
        let num = se2 * se2;
        let den = (var1 / n1) * (var1 / n1) / (n1 - 1.0) + (var2 / n2) * (var2 / n2) / (n2 - 1.0);
        if den <= 0.0 {
            f64::NAN
        } else {
            num / den
        }
    };

    let p_value = if t.is_nan() || df.is_nan() || df <= 0.0 {
        f64::NAN
    } else {
        // напрямую через неполную бета — без потери точности в хвостах
        t_two_tailed_p(t, df)
    };

    WelchResult {
        t,
        df,
        p_value,
        mean1: a.mean,
        sd1: a.sd,
        mean2: b.mean,
        sd2: b.sd,
        n1: a.n,
        n2: b.n,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::summary::summarize;

    /// Golden-значения, полученные в R (set.seed(42)):
    ///   t.test(x, y, var.equal=FALSE) -> t = -1.026509359955,
    ///   df = 52.333972848482, p = 0.309372915729
    #[test]
    fn matches_r_reference() {
        let x = [
            113.709584471467,94.3530182860391,103.631284113373,106.32862604961,
            104.04268323141,98.9387548390852,115.115219974389,99.053409615869,
            120.18423713877,99.3728590094758,113.048696542235,122.866453927011,
            86.1113929888766,97.2121123318263,98.6667866360634,106.359503980701,
            97.1574707858393,73.4354457909522,75.5953307142448,113.201133457302,
            96.9336140592153,82.1869156602,98.2808264424038,112.146746991726,
            118.95193461265,95.695308683938,97.4273061723107,82.3683691480522,
            104.600973548313,93.6000512403988,
        ];
        let y = [
            110.465401478895,113.458048046746,117.421242263639,97.6928834951135,
            111.059461479576,84.3958958511199,95.586491899446,94.7891088698818,
            76.0295082006404,105.433471282707,107.471983202403,100.667312417416,
            114.097958828394,96.2795420750811,88.5806274669685,110.193816310665,
            95.2632818857599,122.329215140655,99.8226455686399,112.867774600826,
            108.863103182447,95.5939327094355,123.908730237504,112.714791668608,
            106.077127759195,
        ];
        let r = welch(&summarize(&x), &summarize(&y));
        assert!((r.t - (-1.026509359955)).abs() < 1e-9, "t: {}", r.t);
        assert!((r.df - 52.333972848482).abs() < 1e-9, "df: {}", r.df);
        assert!((r.p_value - 0.309372915729).abs() < 1e-9, "p: {}", r.p_value);
    }

    #[test]
    fn equal_means_give_p_one() {
        let a = summarize(&[1.0, 2.0, 3.0]);
        let b = summarize(&[1.0, 2.0, 3.0]);
        let r = welch(&a, &b);
        assert!(r.t.abs() < 1e-12);
        assert!((r.p_value - 1.0).abs() < 1e-9);
    }
}
