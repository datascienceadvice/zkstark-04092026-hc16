//! Специальные математические функции для статистики.
//!
//! Все реализации no_std и без внешних крейтов.
//! Целевая точность: совпадение с R в пределах ~1e-9 (машинная f64 для простых,
//! численно устойчивая неполная бета для t/CDF).

/// Логарифм гамма-функции (Lanczos, g=7, n=9), в лог-пространстве.
///
/// Каноническая формула (как в Go `math.Lgamma`):
///   z = x - 1;  t = z + g + 0.5
///   lnGamma(x) = ln(sqrt(2π)) + (z+0.5)·ln(t) - t + ln(ser)
/// с ser = c0 + Σ_{i=1..9} c_i/(z+i), c0 = 0.99999999999980993.
pub fn ln_gamma(x: f64) -> f64 {
    const C: [f64; 9] = [
        0.99999999999980993,
        676.5203681218851,
        -1259.1392167224028,
        771.32342877765313,
        -176.61502916214059,
        12.507343278686905,
        -0.13857109526572012,
        9.9843695780195716e-6,
        1.5056327351493116e-7,
    ];
    const LNSQRT2PI: f64 = 0.91893853320467274178; // ln(sqrt(2*pi))
    const G: f64 = 7.0;

    if x < 0.5 {
        // Формула отражения: Gamma(x) = PI / (sin(PI x) * Gamma(1-x))
        let s = (core::f64::consts::PI * x).sin().abs();
        if s == 0.0 {
            return f64::INFINITY;
        }
        return (core::f64::consts::PI / s).ln() - ln_gamma(1.0 - x);
    }

    let z = x - 1.0;
    let mut ser = C[0];
    for (i, c) in C.iter().enumerate().take(9).skip(1) {
        ser += c / (z + i as f64);
    }
    let t = z + G + 0.5;
    LNSQRT2PI + (z + 0.5) * t.ln() - t + ser.ln()
}

/// Полная бета-функция B(a, b).
pub fn beta(a: f64, b: f64) -> f64 {
    if a <= 0.0 || b <= 0.0 {
        return f64::INFINITY;
    }
    (ln_gamma(a) + ln_gamma(b) - ln_gamma(a + b)).exp()
}

/// Регуляризованная неполная бета-функция I_x(a, b).
///
/// Метод Numerical Recipes (betai): префактор bt из гамма-функций,
/// продолжающаяся дробь betacf, с «переворотом» x -> 1-x для устойчивости.
pub fn ibeta(x: f64, a: f64, b: f64) -> f64 {
    if x <= 0.0 {
        return 0.0;
    }
    if x >= 1.0 {
        return 1.0;
    }

    // bt = x^a (1-x)^b / (a * B(a,b)), в лог-форме.
    let ln_bt = ln_gamma(a + b) - ln_gamma(a) - ln_gamma(b) + a * x.ln() + b * (1.0 - x).ln();
    let bt = ln_bt.exp();

    if x < (a + 1.0) / (a + b + 2.0) {
        bt * betacf(a, b, x) / a
    } else {
        1.0 - bt * betacf(b, a, 1.0 - x) / b
    }
}

/// Продолжающаяся дробь для I_x(a,b). Возвращает h (без префактора).
fn betacf(a: f64, b: f64, x: f64) -> f64 {
    const MAX_IT: usize = 300;
    const EPS: f64 = 3e-14;
    const FP_MIN: f64 = 1e-300;

    let qab = a + b;
    let qap = a + 1.0;
    let qam = a - 1.0;
    let mut c = 1.0;
    let mut d = 1.0 - qab * x / qap;
    if d.abs() < FP_MIN {
        d = FP_MIN;
    }
    d = 1.0 / d;
    let mut h = d;
    let mut m = 0;
    while m < MAX_IT {
        m += 1;
        let mf = m as f64;
        let m2 = 2.0 * mf;
        let mut aa = mf * (b - mf) * x / ((qam + m2) * (a + m2));
        d = 1.0 + aa * d;
        if d.abs() < FP_MIN {
            d = FP_MIN;
        }
        c = 1.0 + aa / c;
        if c.abs() < FP_MIN {
            c = FP_MIN;
        }
        d = 1.0 / d;
        h *= d * c;
        aa = -(a + mf) * (qab + mf) * x / ((a + m2) * (qap + m2));
        d = 1.0 + aa * d;
        if d.abs() < FP_MIN {
            d = FP_MIN;
        }
        c = 1.0 + aa / c;
        if c.abs() < FP_MIN {
            c = FP_MIN;
        }
        d = 1.0 / d;
        let del = d * c;
        h *= del;
        if (del - 1.0).abs() <= EPS {
            break;
        }
    }
    h
}

/// Кумулятивная функция t-распределения Стьюдента: P(T <= x) с df степенями свободы.
///
/// Связь с неполной бета: для x >= 0
///   CDF = 1 - 0.5 * I_{df/(df+x^2)}(df/2, 1/2)
/// (обе стороны симметричны).
pub fn t_cdf(x: f64, df: f64) -> f64 {
    if df <= 0.0 {
        return f64::NAN;
    }
    if x == f64::INFINITY {
        return 1.0;
    }
    if x == f64::NEG_INFINITY {
        return 0.0;
    }
    let a = df / 2.0;
    let z = df / (df + x * x);
    if x >= 0.0 {
        1.0 - 0.5 * ibeta(z, a, 0.5)
    } else {
        0.5 * ibeta(z, a, 0.5)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ln_gamma_known() {
        // ln(Gamma(5)) = ln(24)
        assert!((ln_gamma(5.0) - 24.0_f64.ln()).abs() < 1e-10);
        assert!((ln_gamma(1.0) - 0.0).abs() < 1e-12);
        // рекуррентность: lnGamma(x+1)=lnGamma(x)+ln(x)
        let x = 3.7;
        assert!((ln_gamma(x + 1.0) - (ln_gamma(x) + x.ln())).abs() < 1e-10);
        // ln Gamma(0.5) = ln(sqrt(pi))
        assert!((ln_gamma(0.5) - 0.5 * core::f64::consts::PI.ln()).abs() < 1e-9);
    }

    #[test]
    fn t_cdf_symmetry_and_limits() {
        // p(t=0) = 0.5
        assert!((t_cdf(0.0, 10.0) - 0.5).abs() < 1e-12);
        // симметрия: CDF(-x) = 1 - CDF(x)
        let x = 2.3;
        let df = 7.0;
        assert!((t_cdf(x, df) + t_cdf(-x, df) - 1.0).abs() < 1e-12);
        // df -> inf стремится к нормальному: P(Z<=2) ~ 0.97725
        let big = t_cdf(2.0, 100000.0);
        assert!((0.9772498681 - big).abs() < 1e-4);
    }
}
