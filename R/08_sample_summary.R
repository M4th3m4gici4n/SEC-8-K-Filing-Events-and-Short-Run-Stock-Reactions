# ============================================================
# 08_sample_summary.R
#
# Purpose:
# Create a sample construction summary table.
#
# Inputs:
#   data/interim/company_sample.csv
#   data/interim/filings_8k.csv
#   data/interim/filing_items.csv
#   data/interim/daily_returns.csv
#   data/processed/event_returns.csv
#   data/processed/car_data.csv
#
# Output:
#   output/tables/sample_summary.csv
# ============================================================

library(data.table)

dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)

company_sample <- fread("data/interim/company_sample.csv")
filings_8k <- fread("data/interim/filings_8k.csv")
filing_items <- fread("data/interim/filing_items.csv")
returns <- fread("data/interim/daily_returns.csv")
event_returns <- fread("data/processed/event_returns.csv")
car_data <- fread("data/processed/car_data.csv")

unique_primary_events <- uniqueN(
  event_returns[, paste(ticker, accessionNumber)]
)

sample_summary <- data.table(
  step = c(
    "Current S&P 500 rows after duplicate-CIK removal",
    "Firms with downloaded returns",
    "8-K / 8-K/A filings, 2018-2025",
    "Filing-item rows after item parsing",
    "Unique primary filing events used in main event study",
    "Event-window return rows",
    "Final CAR event observations with complete windows"
  ),
  count = c(
    nrow(company_sample),
    uniqueN(returns$ticker),
    nrow(filings_8k),
    nrow(filing_items),
    unique_primary_events,
    nrow(event_returns),
    nrow(car_data)
  )
)

print(sample_summary)

fwrite(sample_summary, "output/tables/sample_summary.csv")

message("Saved sample summary to output/tables/sample_summary.csv")
