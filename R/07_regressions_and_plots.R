# ============================================================
# 07_regressions_and_plots.R
#
# Purpose:
# Create event-study plots, run CAR regressions, and generate
# regression coefficient plots.
#
# Inputs:
#   data/processed/event_returns_with_ar.csv
#   data/processed/car_data.csv
#
# Outputs:
#   output/figures/average_abnormal_returns_by_item_group.png
#   output/figures/sector_average_car_0_p1.png
#   output/figures/car_coefficients_m1_p1.png
#   output/figures/car_coefficients_0_p1.png
#   output/figures/car_coefficients_0_p5.png
#   output/tables/regression_results.txt
#   output/tables/sector_car_summary.csv
# ============================================================

library(data.table)
library(ggplot2)
library(fixest)
library(broom)
library(lubridate)

# ------------------------------------------------------------
# 1. Create output folders
# ------------------------------------------------------------

dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# 2. Read data
# ------------------------------------------------------------

event_returns <- fread(
  "data/processed/event_returns_with_ar.csv",
  colClasses = list(
    character = c(
      "ticker",
      "cik",
      "accessionNumber",
      "item",
      "item_group",
      "broad_group"
    )
  )
)

car_data <- fread(
  "data/processed/car_data.csv",
  colClasses = list(
    character = c(
      "ticker",
      "cik",
      "accessionNumber",
      "item",
      "item_group",
      "broad_group"
    )
  )
)

event_returns[, filing_date := as.Date(filing_date)]
event_returns[, matched_trading_date := as.Date(matched_trading_date)]
event_returns[, date := as.Date(date)]

car_data[, filing_date := as.Date(filing_date)]
car_data[, matched_trading_date := as.Date(matched_trading_date)]

# ------------------------------------------------------------
# 3. Choose the main event categories
# ------------------------------------------------------------

main_groups <- c(
  "earnings_or_results",
  "leadership_change",
  "material_agreement",
  "merger_acquisition_asset_sale",
  "debt_or_financing_obligation",
  "other_events"
)

event_returns <- event_returns[item_group %in% main_groups]
car_data <- car_data[item_group %in% main_groups]

# Make "other_events" the reference group for regressions.
car_data[, item_group := factor(item_group)]
car_data[, item_group := relevel(item_group, ref = "other_events")]

# Add year variable for fixed effects.
car_data[, year := year(filing_date)]

# ------------------------------------------------------------
# 4. Sector summary after applying the same main-groups filter
# ------------------------------------------------------------
# This requires gics_sector to be preserved in 06_estimate_abnormal_returns.R.

if ("gics_sector" %in% names(car_data)) {

  sector_summary <- car_data[
    ,
    .(
      n_events = .N,
      mean_CAR_0_p1 = mean(CAR_0_p1, na.rm = TRUE),
      median_CAR_0_p1 = median(CAR_0_p1, na.rm = TRUE),
      mean_CAR_0_p5 = mean(CAR_0_p5, na.rm = TRUE)
    ),
    by = gics_sector
  ][order(-n_events)]

  fwrite(sector_summary, "output/tables/sector_car_summary.csv")

  print(sector_summary)

  p_sector <- ggplot(
    sector_summary,
    aes(
      x = reorder(gics_sector, mean_CAR_0_p1),
      y = 100 * mean_CAR_0_p1
    )
  ) +
    geom_col() +
    coord_flip() +
    labs(
      title = "Average CAR[0,+1] by GICS Sector",
      subtitle = "Market-adjusted abnormal returns around 8-K filing dates",
      x = "GICS Sector",
      y = "Average CAR[0,+1], percentage points"
    ) +
    theme_minimal()

  print(p_sector)

  ggsave(
    "output/figures/sector_average_car_0_p1.png",
    p_sector,
    width = 9,
    height = 6,
    dpi = 300
  )

} else {
  warning(
    "gics_sector is not present in car_data. ",
    "Skipping sector summary and sector plot."
  )
}

# ------------------------------------------------------------
# 5. Event-time plot: average abnormal returns
# ------------------------------------------------------------

avg_ar <- event_returns[
  ,
  .(
    mean_ar = mean(abnormal_ret, na.rm = TRUE),
    se_ar = sd(abnormal_ret, na.rm = TRUE) / sqrt(.N),
    n = .N
  ),
  by = .(item_group, event_time)
]

# 95% confidence interval.
avg_ar[, ci_low := mean_ar - 1.96 * se_ar]
avg_ar[, ci_high := mean_ar + 1.96 * se_ar]

p_avg_ar <- ggplot(
  avg_ar,
  aes(x = event_time, y = mean_ar)
) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_ribbon(
    aes(ymin = ci_low, ymax = ci_high),
    alpha = 0.20
  ) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.8) +
  facet_wrap(~ item_group, scales = "free_y") +
  labs(
    title = "Average Abnormal Returns Around 8-K Filing Dates",
    subtitle = "Market-adjusted abnormal returns using SPY as the market benchmark",
    x = "Trading Days Relative to Filing Date",
    y = "Average Abnormal Return"
  ) +
  theme_minimal()

print(p_avg_ar)

ggsave(
  filename = "output/figures/average_abnormal_returns_by_item_group.png",
  plot = p_avg_ar,
  width = 11,
  height = 7,
  dpi = 300
)

# ------------------------------------------------------------
# 6. Regressions: CARs by 8-K item group
# ------------------------------------------------------------
# Model 1: simple difference by item group.
# Model 2: ticker fixed effects + year fixed effects.
#
# Interpretation:
# Coefficients are average CAR differences relative to other_events.
# They should be described as short-run reactions associated with
# item categories, not as definitive causal effects.

model_m1_p1_simple <- feols(
  CAR_m1_p1 ~ i(item_group, ref = "other_events"),
  data = car_data,
  cluster = ~ ticker
)

model_m1_p1_fe <- feols(
  CAR_m1_p1 ~ i(item_group, ref = "other_events") | ticker + year,
  data = car_data,
  cluster = ~ ticker
)

model_0_p1_simple <- feols(
  CAR_0_p1 ~ i(item_group, ref = "other_events"),
  data = car_data,
  cluster = ~ ticker
)

model_0_p1_fe <- feols(
  CAR_0_p1 ~ i(item_group, ref = "other_events") | ticker + year,
  data = car_data,
  cluster = ~ ticker
)

model_0_p5_simple <- feols(
  CAR_0_p5 ~ i(item_group, ref = "other_events"),
  data = car_data,
  cluster = ~ ticker
)

model_0_p5_fe <- feols(
  CAR_0_p5 ~ i(item_group, ref = "other_events") | ticker + year,
  data = car_data,
  cluster = ~ ticker
)

# Print regression summaries.
summary(model_m1_p1_simple)
summary(model_m1_p1_fe)
summary(model_0_p1_simple)
summary(model_0_p1_fe)
summary(model_0_p5_simple)
summary(model_0_p5_fe)

# ------------------------------------------------------------
# 7. Save regression table
# ------------------------------------------------------------

etable(
  model_m1_p1_simple,
  model_m1_p1_fe,
  model_0_p1_simple,
  model_0_p1_fe,
  model_0_p5_simple,
  model_0_p5_fe,
  file = "output/tables/regression_results.txt"
)

# ------------------------------------------------------------
# 8. Helper function for regression coefficient plots
# ------------------------------------------------------------

plot_item_group_coefficients <- function(model, title, filename) {

  coef_dt <- as.data.table(
    broom::tidy(model, conf.int = TRUE)
  )

  # Keep only item_group coefficients.
  coef_dt <- coef_dt[grepl("item_group", term)]

  if (nrow(coef_dt) == 0) {
    warning("No item_group coefficients found for plot: ", title)
    return(NULL)
  }

  # Clean coefficient labels.
  coef_dt[, item_group := gsub("item_group::", "", term)]
  coef_dt[, item_group := gsub(":.*", "", item_group)]
  coef_dt[, item_group := gsub("_", " ", item_group)]

  # Convert from decimal returns to percentage points.
  coef_dt[, estimate_pp := 100 * estimate]
  coef_dt[, conf_low_pp := 100 * conf.low]
  coef_dt[, conf_high_pp := 100 * conf.high]

  p <- ggplot(
    coef_dt,
    aes(
      x = reorder(item_group, estimate_pp),
      y = estimate_pp
    )
  ) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_pointrange(
      aes(ymin = conf_low_pp, ymax = conf_high_pp)
    ) +
    coord_flip() +
    labs(
      title = title,
      subtitle = "Coefficients relative to other_events; 95% confidence intervals",
      x = "8-K Item Group",
      y = "Coefficient, percentage points"
    ) +
    theme_minimal()

  print(p)

  ggsave(
    filename = filename,
    plot = p,
    width = 9,
    height = 6,
    dpi = 300
  )

  p
}

# ------------------------------------------------------------
# 9. Generate coefficient plots
# ------------------------------------------------------------

p_coef_m1_p1 <- plot_item_group_coefficients(
  model = model_m1_p1_fe,
  title = "Regression Coefficients for CAR[-1,+1]",
  filename = "output/figures/car_coefficients_m1_p1.png"
)

p_coef_0_p1 <- plot_item_group_coefficients(
  model = model_0_p1_fe,
  title = "Regression Coefficients for CAR[0,+1]",
  filename = "output/figures/car_coefficients_0_p1.png"
)

p_coef_0_p5 <- plot_item_group_coefficients(
  model = model_0_p5_fe,
  title = "Regression Coefficients for CAR[0,+5]",
  filename = "output/figures/car_coefficients_0_p5.png"
)
