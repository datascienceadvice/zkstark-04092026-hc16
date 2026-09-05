//! Критерий Шапиро–Уилка (порт R `shapiro.test`).
//!
//! Основа — C-трансляция AS R94 (`src/library/stats/src/swilk.c`) + обёртка
//! `shapiro.test.R`: сортировка, проверки n∈[3,5000], ненулевой размах,
//! «перемасштабирование» при rng < 1e-10. Точность совпадает с R 4.3.x.

use crate::special::{normal_quantile, normal_upper_tail};

/// Результат критерия Шапиро–Уилка.
#[derive(serde::Serialize, serde::Deserialize, Clone, Copy, Debug, PartialEq)]
pub struct ShapiroResult {
    pub w: f64,
    pub p_value: f64,
}

/// Погрешность «одного» значения, как в swilk.c (`small = 1e-19`).
const SMALL: f64 = 1e-19;

/// Полином AS 181.2: `cc[0] + cc[1]·x + ... + cc[nord-1]·x^(nord-1)`.
fn poly(cc: &[f64], x: f64) -> f64 {
    let nord = cc.len();
    if nord <= 1 {
        return cc[0];
    }
    let mut p = x * cc[nord - 1];
    let mut j = nord - 2;
    while j > 0 {
        p = (p + cc[j]) * x;
        j -= 1;
    }
    cc[0] + p
}

fn sign(v: i64) -> f64 {
    if v > 0 {
        1.0
    } else if v < 0 {
        -1.0
    } else {
        0.0
    }
}

fn min_idx(i: i64, j: i64) -> usize {
    if i < j {
        i as usize
    } else {
        j as usize
    }
}

/// Вычисление W и p-value по отсортированной выборке (без проверок).
fn swilk(x: &[f64]) -> ShapiroResult {
    let n = x.len() as i64;
    let nn2 = (n / 2) as usize;

    // Коэффициенты полиномов swilk.c
    const G: [f64; 2] = [-2.273, 0.459];
    const C1: [f64; 6] = [0.0, 0.221157, -0.147981, -2.07119, 4.434685, -2.706056];
    const C2: [f64; 6] = [0.0, 0.042981, -0.293762, -1.752461, 5.682633, -3.582633];
    const C3: [f64; 4] = [0.544, -0.39978, 0.025054, -6.714e-4];
    const C4: [f64; 4] = [1.3822, -0.77857, 0.062767, -0.0020322];
    const C5: [f64; 4] = [-1.5861, -0.31082, -0.083751, 0.0038915];
    const C6: [f64; 3] = [-0.4803, -0.082676, 0.0030302];

    let mut a = vec![0.0f64; nn2 + 1]; // a[1..=nn2]
    let an = n as f64;

    if n == 3 {
        a[1] = 0.70710678; // sqrt(1/2)
    } else {
        let an25 = an + 0.25;
        let mut summ2 = 0.0;
        for i in 1..=nn2 {
            a[i] = normal_quantile((i as f64 - 0.375) / an25);
            summ2 += a[i] * a[i];
        }
        summ2 *= 2.0;
        let ssumm2 = summ2.sqrt();
        let rsn = 1.0 / an.sqrt();
        let a1 = poly(&C1, rsn) - a[1] / ssumm2;

        // Нормализация a[]
        let i1: usize;
        let fac;
        if n > 5 {
            i1 = 3;
            let a2 = -a[2] / ssumm2 + poly(&C2, rsn);
            fac = ((summ2 - 2.0 * (a[1] * a[1]) - 2.0 * (a[2] * a[2]))
                / (1.0 - 2.0 * (a1 * a1) - 2.0 * (a2 * a2)))
                .sqrt();
            a[2] = a2;
        } else {
            i1 = 2;
            fac = ((summ2 - 2.0 * (a[1] * a[1])) / (1.0 - 2.0 * (a1 * a1))).sqrt();
        }
        a[1] = a1;
        for i in i1..=nn2 {
            a[i] /= -fac;
        }
    }

    // Размах после перемасштабирования обёрткой всегда не меньше 1e-10;
    // внутренняя проверка swilk.c (range < 1e-19) не срабатывает, но
    // оставляем для строгого соответствия.
    let range = x[x.len() - 1] - x[0];
    debug_assert!(range >= SMALL, "range too small");

    // Первое накопление: sx, sa
    let mut sx = x[0] / range;
    let mut sa = -a[1];
    let mut i = 1i64;
    let mut j = n - 1;
    while i < n {
        let xi = x[i as usize] / range;
        sx += xi;
        i += 1;
        if i != j {
            sa += sign(i - j) * a[min_idx(i, j)];
        }
        j -= 1;
    }

    // Второе накопление: ssa, ssx, sax
    sa /= n as f64;
    sx /= n as f64;
    let mut ssa = 0.0;
    let mut ssx = 0.0;
    let mut sax = 0.0;
    let mut i = 0i64;
    let mut j = n - 1;
    while i < n {
        let asa = if i != j {
            sign(i - j) * a[1 + min_idx(i, j)] - sa
        } else {
            -sa
        };
        let xsx = x[i as usize] / range - sx;
        ssa += asa * asa;
        ssx += xsx * xsx;
        sax += asa * xsx;
        i += 1;
        j -= 1;
    }

    let ssassx = (ssa * ssx).sqrt();
    let w1 = (ssassx - sax) * (ssassx + sax) / (ssa * ssx);
    let w = 1.0 - w1;

    // Уровень значимости
    if n == 3 {
        let pi6 = 1.90985931710274; // 6/pi
        let stqr = 1.04719755119660; // asin(sqrt(3/4))
        let mut p = pi6 * (w.sqrt().asin() - stqr);
        if p < 0.0 {
            p = 0.0;
        }
        return ShapiroResult { w, p_value: p };
    }

    let y = w1.ln();
    let xx = an.ln();
    let (y, m, s) = if n <= 11 {
        let gamma = poly(&G, an);
        if y >= gamma {
            return ShapiroResult {
                w,
                p_value: 1e-99,
            };
        }
        let y = -(gamma - y).ln();
        let m = poly(&C3, an);
        let s = poly(&C4, an).exp();
        (y, m, s)
    } else {
        let m = poly(&C5, xx);
        let s = poly(&C6, xx).exp();
        (y, m, s)
    };

    let p = normal_upper_tail((y - m) / s);
    ShapiroResult { w, p_value: p }
}

/// Критерий Шапиро–Уилка, повторяющий `shapiro.test(x)` из R.
///
/// Возвращает Err с текстом ошибки R для недопустимых выборок.
pub fn shapiro_wilk(x: &[f64]) -> Result<ShapiroResult, &'static str> {
    let n = x.len();
    if n < 3 {
        return Err("sample size must be at least 3");
    }
    if n > 5000 {
        return Err("sample size must be at most 5000");
    }

    let mut x = x.to_vec();
    x.sort_by(|a, b| a.partial_cmp(b).unwrap_or(core::cmp::Ordering::Equal));

    let rng = x[n - 1] - x[0];
    if rng == 0.0 {
        return Err("all 'x' values are identical");
    }
    if rng < 1e-10 {
        for v in x.iter_mut() {
            *v /= rng;
        }
    }

    if x[n - 1] - x[0] < SMALL {
        return Err("range too small");
    }

    Ok(swilk(&x))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn r_verbatim_c_1_2_3_4_5() {
        // R 4.3.1: shapiro.test(1:5) -> W=0.98676215544771939, p=0.9671739359680398
        let r = shapiro_wilk(&[1.0, 2.0, 3.0, 4.0, 5.0]).unwrap();
        assert!((r.w - 0.9867621554477194).abs() < 1e-12, "w={}", r.w);
        assert!((r.p_value - 0.9671739359680398).abs() < 1e-12, "p={}", r.p_value);
    }

    #[test]
    fn r_verbatim_small_n() {
        // Ручные эталоны R 4.3.1 (без seed — целые прогрессии)
        let cases: &[(&[f64], f64, f64)] = &[
            (&[1.0, 2.0, 3.0], 1.0, 0.9999999999999933), // n=3
            (&[1.0, 2.0, 3.0, 4.0], 0.9929120068006192, 0.9718770576208972),
            (&[1.0, 2.0, 3.0, 4.0, 5.0, 6.0], 0.9818894288631076, 0.9605549608007036),
            (
                &[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0],
                0.9683912805170447,
                0.8698423287837864,
            ),
            (
                &[0.1, 0.3, 0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 1.7, 1.9, 2.1, 2.3],
                0.9668963632914048,
                0.8757314433658767,
            ),
        ];
        for (x, ew, ep) in cases {
            let r = shapiro_wilk(x).unwrap();
            assert!((r.w - ew).abs() < 1e-12, "n={} w={}", x.len(), r.w);
            assert!((r.p_value - ep).abs() < 1e-12, "n={} p={}", x.len(), r.p_value);
        }
    }

    #[test]
    fn rejects_bad_inputs() {
        assert!(shapiro_wilk(&[1.0, 2.0]).is_err());
        assert!(shapiro_wilk(&[1.0; 10]).is_err());
        let big = vec![1.0; 5001];
        assert!(shapiro_wilk(&big).is_err());
    }
}