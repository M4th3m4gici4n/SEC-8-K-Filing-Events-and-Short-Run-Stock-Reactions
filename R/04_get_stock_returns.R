# ============================================================
# 04_get_stock_returns.R
#
# Purpose:
# Download daily stock prices for the sample firms, compute
# daily returns, add SPY market returns, and save the return data.
#
# Input:
#   data/interim/company_sample.csv
#
# Output:
#   data/interim/daily_returns.csv
# ============================================================

library(data.table)
library(stringr)
library(lubridate)
library(quantmod)

dir.create("data/interim", recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# 1. Read company sample
# ------------------------------------------------------------

company_sample <- fread(
  "data/interim/company_sample.csv",
  colClasses = list(character = c("ticker", "yahoo_ticker", "cik_str"))
)

company_sample[, cik_str := str_pad(
  cik_str,
  width = 10,
  side = "left",
  pad = "0"
)]

# ------------------------------------------------------------
# 2. Define date range
# ------------------------------------------------------------
# Prices start before the event sample so later extensions can
# estimate market models using pre-event estimation windows.

price_start <- "2017-01-01"
price_end <- "2025-12-31"

# ------------------------------------------------------------
# 3. Price download function
# ------------------------------------------------------------

get_prices <- function(ticker, yahoo_ticker, from, to) {

  message("Downloading prices for: ", ticker, " using Yahoo ticker: ", yahoo_ticker)

  x <- tryCatch(
    getSymbols(
      Symbols = yahoo_ticker,
      src = "yahoo",
      from = from,
      to = to,
      auto.assign = FALSE
    ),
    error = function(e) {
      message("Failed price download for: ", ticker, " / ", yahoo_ticker)
      message("Error: ", e$message)
      NULL
    }
  )

  if (is.null(x)) {
    return(NULL)
  }

  dt <- data.table(
    date = as.Date(index(x)),
    ticker = ticker,
    yahoo_ticker = yahoo_ticker,
    adjusted = as.numeric(Ad(x))
  )

  setorder(dt, date)
  dt[, ret := adjusted / shift(adjusted) - 1]

  dt
}

# ------------------------------------------------------------
# 4. Download prices for all firms
# ------------------------------------------------------------

prices <- rbindlist(
  lapply(seq_len(nrow(company_sample)), function(i) {

    out <- get_prices(
      ticker = company_sample$ticker[i],
      yahoo_ticker = company_sample$yahoo_ticker[i],
      from = price_start,
      to = price_end
    )

    Sys.sleep(0.10)

    out
  }),
  fill = TRUE
)

# ------------------------------------------------------------
# 5. Download market benchmark, SPY
# ------------------------------------------------------------

market_prices <- get_prices(
  ticker = "SPY",
  yahoo_ticker = "SPY",
  from = price_start,
  to = price_end
)

if (is.null(market_prices)) {
  stop("SPY market benchmark failed to download. Cannot compute market-adjusted returns.")
}

setnames(market_prices, "ret", "mkt_ret")

market_prices <- market_prices[, .(
  date,
  mkt_adjusted = adjusted,
  mkt_ret
)]

# ------------------------------------------------------------
# 6. Merge firm returns with market returns
# ------------------------------------------------------------

returns <- merge(
  prices,
  market_prices,
  by = "date",
  all.x = TRUE
)

returns <- returns[
  !is.na(ret) &
    !is.na(mkt_ret)
]

# ------------------------------------------------------------
# 7. Add company metadata
# ------------------------------------------------------------

returns <- merge(
  returns,
  company_sample[, .(
    ticker,
    cik_str,
    title,
    gics_sector,
    gics_sub_industry
  )],
  by = "ticker",
  all.x = TRUE
)

setnames(returns, "cik_str", "cik")

returns[, cik := str_pad(
  cik,
  width = 10,
  side = "left",
  pad = "0"
)]

# ------------------------------------------------------------
# 8. Add trading-day index
# ------------------------------------------------------------

setorder(returns, ticker, date)

returns[, trading_day := seq_len(.N), by = ticker]

# ------------------------------------------------------------
# 9. Print checks
# ------------------------------------------------------------

message("Number of return rows:")
print(nrow(returns))

message("Number of tickers with returns:")
print(uniqueN(returns$ticker))

message("Date range by ticker:")
print(returns[, .(
  first_date = min(date),
  last_date = max(date),
  n_days = .N
), by = ticker][order(ticker)][1:20])

message("Tickers missing returns:")
missing_returns <- company_sample[
  !ticker %in% unique(returns$ticker),
  .(ticker, yahoo_ticker, title)
]
print(missing_returns)

# ------------------------------------------------------------
# 10. Save
# ------------------------------------------------------------

fwrite(returns, "data/interim/daily_returns.csv")

message("Saved expanded daily returns to data/interim/daily_returns.csv")
