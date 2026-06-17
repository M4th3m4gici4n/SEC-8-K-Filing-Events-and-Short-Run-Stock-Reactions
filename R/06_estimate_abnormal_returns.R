# ============================================================
# 06_estimate_abnormal_returns.R
#
# Purpose:
# Estimate abnormal returns and cumulative abnormal returns
# around SEC 8-K filing events.
#
# Beginner version:
#   abnormal return = firm return - market return
#
# Inputs:
#   data/processed/event_returns.csv
#
# Outputs:
#   data/processed/event_returns_with_ar.csv
#   data/processed/car_data.csv
#   output/tables/car_summary.csv
# ============================================================

library(data.table)
library(stringr)
library(lubridate)

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# 1. Read event-window return data
# ------------------------------------------------------------

event_returns <- fread(
  "data/processed/event_returns.csv",
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

# Make sure dates are dates.
event_returns[, filing_date := as.Date(filing_date)]
event_returns[, matched_trading_date := as.Date(matched_trading_date)]
event_returns[, date := as.Date(date)]

# Make sure identifiers are clean.
event_returns[, cik := str_pad(cik, width = 10, side = "left", pad = "0")]

# ------------------------------------------------------------
# 2. Compute market-adjusted abnormal returns
# ------------------------------------------------------------
# Beginner event-study abnormal return:
#
#   abnormal_ret = firm return - market return
#
# If a firm rises 2% and the market rises 0.5%, then the
# abnormal return is 1.5%.

event_returns[, abnormal_ret := ret - mkt_ret]

# ------------------------------------------------------------
# 3. Basic sanity checks
# ------------------------------------------------------------

message("Preview with abnormal returns:")
print(head(event_returns[, .(
  ticker,
  filing_date,
  matched_trading_date,
  item,
  item_group,
  event_time,
  date,
  ret,
  mkt_ret,
  abnormal_ret
)]))

message("Average abnormal return by event time:")
print(event_returns[, .(
  mean_abnormal_ret = mean(abnormal_ret, na.rm = TRUE),
  n = .N
), by = event_time][order(event_time)])

# ------------------------------------------------------------
# 4. Function to compute cumulative abnormal returns
# ------------------------------------------------------------
# CAR means cumulative abnormal return.
#
# Example:
# CAR[-1,+1] = abnormal return on day -1
#            + abnormal return on day 0
#            + abnormal return on day +1

make_car <- function(dt, start_day, end_day, car_name) {

  out <- dt[
    event_time >= start_day &
      event_time <= end_day,
    .(
      CAR = sum(abnormal_ret, na.rm = TRUE),
      n_days = .N
    ),
    by = .(
      ticker,
      cik,
      accessionNumber,
      filing_date,
      matched_trading_date,
      item,
      item_group,
      broad_group,
      gics_sector,
      gics_sub_industry
    )
  ]

  setnames(out, "CAR", car_name)
  setnames(out, "n_days", paste0("n_days_", car_name))

  out
}

# ------------------------------------------------------------
# 5. Compute common event-study CAR windows
# ------------------------------------------------------------

car_m1_p1 <- make_car(event_returns, -1, 1, "CAR_m1_p1")
car_0_p1  <- make_car(event_returns,  0, 1, "CAR_0_p1")
car_0_p5  <- make_car(event_returns,  0, 5, "CAR_0_p5")
car_m5_p5 <- make_car(event_returns, -5, 5, "CAR_m5_p5")

# ------------------------------------------------------------
# 6. Merge all CAR windows into one event-level dataset
# ------------------------------------------------------------

merge_keys <- c(
  "ticker",
  "cik",
  "accessionNumber",
  "filing_date",
  "matched_trading_date",
  "item",
  "item_group",
  "broad_group",
  "gics_sector",
  "gics_sub_industry"
)

car_data <- Reduce(
  function(x, y) {
    merge(x, y, by = merge_keys, all = TRUE)
  },
  list(car_m1_p1, car_0_p1, car_0_p5, car_m5_p5)
)

# ------------------------------------------------------------
# 7. Keep only complete CAR windows
# ------------------------------------------------------------
# For example, CAR[-1,+1] should have 3 trading days.
# CAR[0,+1] should have 2 trading days.
# CAR[0,+5] should have 6 trading days.
# CAR[-5,+5] should have 11 trading days.

car_data <- car_data[
  n_days_CAR_m1_p1 == 3 &
    n_days_CAR_0_p1 == 2 &
    n_days_CAR_0_p5 == 6 &
    n_days_CAR_m5_p5 == 11
]

# ------------------------------------------------------------
# 8. Summarize CARs by 8-K item group
# ------------------------------------------------------------

car_summary <- car_data[
  ,
  .(
    n_events = .N,
    mean_CAR_m1_p1 = mean(CAR_m1_p1, na.rm = TRUE),
    median_CAR_m1_p1 = median(CAR_m1_p1, na.rm = TRUE),
    mean_CAR_0_p1 = mean(CAR_0_p1, na.rm = TRUE),
    median_CAR_0_p1 = median(CAR_0_p1, na.rm = TRUE),
    mean_CAR_0_p5 = mean(CAR_0_p5, na.rm = TRUE),
    median_CAR_0_p5 = median(CAR_0_p5, na.rm = TRUE),
    mean_CAR_m5_p5 = mean(CAR_m5_p5, na.rm = TRUE),
    median_CAR_m5_p5 = median(CAR_m5_p5, na.rm = TRUE)
  ),
  by = item_group
][order(-n_events)]

message("Preview of CAR data:")
print(head(car_data[, .(
  ticker,
  filing_date,
  matched_trading_date,
  item,
  item_group,
  gics_sector,
  CAR_m1_p1,
  CAR_0_p1,
  CAR_0_p5,
  CAR_m5_p5
)]))

message("CAR summary by item group:")
print(car_summary)

# ------------------------------------------------------------
# 9. Save outputs
# ------------------------------------------------------------

fwrite(event_returns, "data/processed/event_returns_with_ar.csv")
fwrite(car_data, "data/processed/car_data.csv")
fwrite(car_summary, "output/tables/car_summary.csv")

message("Saved abnormal-return data to data/processed/event_returns_with_ar.csv")
message("Saved CAR data to data/processed/car_data.csv")
message("Saved CAR summary to output/tables/car_summary.csv")
