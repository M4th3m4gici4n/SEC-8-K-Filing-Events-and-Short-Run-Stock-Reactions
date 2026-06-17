# ============================================================
# 05_build_event_windows.R
#
# Purpose:
# Merge 8-K filing events to daily stock returns and create
# event windows such as [-5, +5] trading days around each filing.
#
# Main analysis choice:
# This script creates a PRIMARY-ITEM event dataset with one row
# per filing accession number. This avoids double-counting the
# same stock return reaction when a single 8-K has multiple item
# codes.
#
# Inputs:
#   data/interim/filing_items.csv
#   data/interim/daily_returns.csv
#
# Outputs:
#   data/processed/event_returns.csv
#   data/processed/events_primary.csv
# ============================================================

library(data.table)
library(stringr)
library(lubridate)

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# 1. Read filing events and daily returns
# ------------------------------------------------------------

filing_items <- fread(
  "data/interim/filing_items.csv",
  colClasses = list(
    character = c("ticker", "cik", "accessionNumber", "item", "item_group", "broad_group")
  )
)

returns <- fread(
  "data/interim/daily_returns.csv",
  colClasses = list(
    character = c("ticker", "cik")
  )
)

# Make sure dates are dates
filing_items[, filing_date := as.Date(filing_date)]
returns[, date := as.Date(date)]

# Make sure identifiers are clean
filing_items[, cik := str_pad(cik, width = 10, side = "left", pad = "0")]
returns[, cik := str_pad(cik, width = 10, side = "left", pad = "0")]

# ------------------------------------------------------------
# 2. Keep only useful event categories
# ------------------------------------------------------------
# Item 9.01 is usually exhibits/financial statements attached to
# another event. For the main event study, we usually do not want
# to treat 9.01 as its own economic event.

main_events <- filing_items[
  item_group %in% c(
    "earnings_or_results",
    "leadership_change",
    "material_agreement",
    "termination_of_material_agreement",
    "merger_acquisition_asset_sale",
    "debt_or_financing_obligation",
    "other_events"
  )
]

# ------------------------------------------------------------
# 3. Keep one primary item per filing
# ------------------------------------------------------------
# A single 8-K can contain multiple economically meaningful item
# codes. If we keep all of them, the same return reaction may
# enter the analysis more than once. For the main analysis, keep
# the highest-priority item for each accession number.

if (!"item_priority" %in% names(main_events)) {
  main_events[, item_priority := fifelse(item == "2.02", 1,
                                  fifelse(item == "2.01", 2,
                                  fifelse(item == "1.01", 3,
                                  fifelse(item == "1.02", 4,
                                  fifelse(item == "2.03", 5,
                                  fifelse(item == "5.02", 6,
                                  fifelse(item == "8.01", 7, 99)))))))]
}

setorder(main_events, ticker, accessionNumber, item_priority)

main_events_primary <- main_events[
  ,
  .SD[1],
  by = .(ticker, accessionNumber)
]

# ------------------------------------------------------------
# 4. Add trading-day index to returns
# ------------------------------------------------------------
# Calendar days are not enough because markets close on weekends
# and holidays. So we number each trading day for each ticker.

setorder(returns, ticker, date)

returns[, trading_day := seq_len(.N), by = ticker]

# ------------------------------------------------------------
# 5. Attach each filing to a trading day
# ------------------------------------------------------------

# Make copies so we do not accidentally modify the original objects.
returns_for_match <- copy(returns)
events_for_match <- copy(main_events_primary)

# Keep a separate copy of the trading date before the join.
returns_for_match[, matched_trading_date := date]

# Rename filing_date so the original event date survives the join clearly.
setnames(events_for_match, "filing_date", "event_filing_date")

# Sort before rolling join.
setorder(returns_for_match, ticker, date)
setorder(events_for_match, ticker, event_filing_date)

# Match each filing to the next available trading day.
# This avoids assigning weekend/holiday filings to a trading day
# before the filing became public.
events <- returns_for_match[
  events_for_match,
  on = .(ticker, date = event_filing_date),
  roll = -Inf
]

# ------------------------------------------------------------
# 6. Keep clean event-level information
# ------------------------------------------------------------

events <- events[, .(
  ticker,
  yahoo_ticker,
  cik = i.cik,
  title = i.title,
  gics_sector = i.gics_sector,
  gics_sub_industry = i.gics_sub_industry,
  accessionNumber,
  filing_date = event_filing_date,
  matched_trading_date,
  event_trading_day = trading_day,
  item,
  item_group,
  broad_group
)]

events <- events[!is.na(event_trading_day)]

# ------------------------------------------------------------
# 7. Create event-window returns
# ------------------------------------------------------------

build_event_window <- function(events, returns, window = 5) {

  # Join every event to all return rows for the same ticker.
  # This creates a large table, so allow.cartesian = TRUE is required.
  out <- returns[
    events,
    on = "ticker",
    allow.cartesian = TRUE
  ]

  # Relative trading day:
  # 0 means filing date/matched trading day
  # -1 means one trading day before filing
  # +1 means one trading day after filing
  out[, event_time := trading_day - event_trading_day]

  # Keep only the event window.
  out <- out[
    event_time >= -window &
      event_time <= window
  ]

  out
}

event_returns <- build_event_window(
  events = events,
  returns = returns,
  window = 5
)

# ------------------------------------------------------------
# 8. Clean final event-window dataset
# ------------------------------------------------------------

event_returns <- event_returns[, .(
  ticker,
  yahoo_ticker,
  cik = i.cik,
  title = i.title,
  gics_sector = i.gics_sector,
  gics_sub_industry = i.gics_sub_industry,
  accessionNumber,
  filing_date,
  matched_trading_date,
  item,
  item_group,
  broad_group,
  event_time,
  date,
  trading_day,
  ret,
  mkt_ret,
  adjusted,
  mkt_adjusted
)]

setorder(event_returns, ticker, accessionNumber, item, event_time)

# ------------------------------------------------------------
# 9. Print checks
# ------------------------------------------------------------

message("Number of primary filing events:")
print(nrow(events))

message("Number of event-window return rows:")
print(nrow(event_returns))

message("Event-time counts:")
print(event_returns[, .N, by = event_time][order(event_time)])

message("Check for duplicated accession numbers in primary events:")
print(events[, .N, by = .(ticker, accessionNumber)][N > 1][1:20])

message("Preview:")
print(head(event_returns, 20))

# ------------------------------------------------------------
# 10. Save event-level and event-window datasets
# ------------------------------------------------------------

fwrite(events, "data/processed/events_primary.csv")
fwrite(event_returns, "data/processed/event_returns.csv")

message("Saved primary events to data/processed/events_primary.csv")
message("Saved event-window returns to data/processed/event_returns.csv")
