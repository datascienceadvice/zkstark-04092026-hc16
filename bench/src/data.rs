//! Загрузка сценариев (scenarios.csv) и golden-значений (golden.csv).

use crate::types::{GoldenValues, Scenario};
use std::collections::HashMap;
use std::error::Error;

/// Читает scenarios.csv (case, group, value) и scenario_meta.csv (case,name,alpha,n1,n2).
pub fn load_scenarios(scenarios_path: &str, meta_path: &str) -> Result<Vec<Scenario>, Box<dyn Error>> {
    let mut meta: HashMap<String, (String, f64)> = HashMap::new();
    let mut rdr = csv::Reader::from_path(meta_path)?;
    for rec in rdr.records() {
        let rec = rec?;
        let id = rec[0].to_string();
        let name = rec[1].to_string();
        let alpha: f64 = rec[2].parse()?;
        meta.insert(id, (name, alpha));
    }

    let mut groups: HashMap<String, (Vec<f64>, Vec<f64>)> = HashMap::new();
    let mut rdr = csv::Reader::from_path(scenarios_path)?;
    for rec in rdr.records() {
        let rec = rec?;
        let id = rec[0].to_string();
        let group: i32 = rec[1].parse()?;
        let value: f64 = rec[2].parse()?;
        let e = groups.entry(id).or_default();
        if group == 1 {
            e.0.push(value);
        } else {
            e.1.push(value);
        }
    }

    let mut out = Vec::new();
    for (id, g) in groups {
        let (name, alpha) = meta.get(&id).cloned().unwrap_or((id.clone(), 0.05));
        out.push(Scenario {
            id: id.clone(),
            name,
            alpha,
            group1: g.0,
            group2: g.1,
        });
    }
    out.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(out)
}

/// Читает golden.csv (case, metric, value) -> карту.
pub fn load_golden(golden_path: &str) -> Result<GoldenValues, Box<dyn Error>> {
    let mut map: GoldenValues = HashMap::new();
    let mut rdr = csv::Reader::from_path(golden_path)?;
    for rec in rdr.records() {
        let rec = rec?;
        let case = rec[0].to_string();
        let metric = rec[1].to_string();
        let raw = rec[2].trim();
        if raw == "NA" || raw.is_empty() {
            continue;
        }
        let value: f64 = raw.parse()?;
        map.entry(case).or_insert_with(HashMap::new).insert(metric, value);
    }
    Ok(map)
}

/// Для сценария возвращает golden-значение метрики.
pub fn golden(g: &GoldenValues, case: &str, metric: &str) -> Option<f64> {
    g.get(case).and_then(|m| m.get(metric).copied())
}