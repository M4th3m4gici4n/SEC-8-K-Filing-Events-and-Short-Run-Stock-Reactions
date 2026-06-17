# ============================================================
# 01_get_companies.R
#
# Purpose:
# Download the current S&P 500 constituent list and create a
# company sample for the SEC 8-K event study.
#
# Important limitation:
# This uses the CURRENT S&P 500 list from Wikipedia. Therefore,
# the sample is a current-large-cap sample, not a historically
# balanced S&P 500 panel. This creates survivorship bias if the
# analysis is interpreted as "the S&P 500 from 2018-2025."
#
# Output:
#   data/interim/company_sample.csv
# ============================================================

library(data.table)
library(rvest)
library(stringr)

# ------------------------------------------------------------
# 1. Create output folder
# ------------------------------------------------------------

dir.create("data/interim", recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# 2. Download current S&P 500 constituents
# ------------------------------------------------------------
# Wikipedia has a convenient table with ticker, company name,
# sector, date added, and CIK.

sp500_url <- "https://en.wikipedia.org/wiki/List_of_S%26P_500_companies"

sp500_tables <- rvest::read_html(sp500_url) |>
  rvest::html_table(fill = TRUE)

sp500 <- as.data.table(sp500_tables[[1]])

# ------------------------------------------------------------
# 3. Clean column names
# ------------------------------------------------------------

setnames(
  sp500,
  old = c(
    "Symbol",
    "Security",
    "GICS Sector",
    "GICS Sub-Industry",
    "Headquarters Location",
    "Date added",
    "CIK",
    "Founded"
  ),
  new = c(
    "ticker",
    "title",
    "gics_sector",
    "gics_sub_industry",
    "headquarters",
    "date_added",
    "cik_str",
    "founded"
  )
)

# ------------------------------------------------------------
# 4. Clean ticker and CIK
# ------------------------------------------------------------

sp500[, ticker := toupper(ticker)]

# Yahoo Finance uses BRK-B and BF-B instead of BRK.B and BF.B.
# SEC uses CIK, so the CIK is fine either way, but Yahoo needs
# the ticker format adjusted later.
sp500[, yahoo_ticker := str_replace_all(ticker, "\\.", "-")]

sp500[, cik_str := str_pad(
  as.character(cik_str),
  width = 10,
  side = "left",
  pad = "0"
)]

sp500[, date_added := as.Date(date_added)]

# ------------------------------------------------------------
# 5. Keep useful columns
# ------------------------------------------------------------

company_sample <- sp500[, .(
  ticker,
  yahoo_ticker,
  title,
  cik_str,
  gics_sector,
  gics_sub_industry,
  date_added
)]

setorder(company_sample, ticker)

# ------------------------------------------------------------
# 6. Remove duplicate CIKs
# ------------------------------------------------------------
# Some S&P 500 companies have multiple share classes.
# For this beginner event study, keep one ticker per SEC CIK
# so that SEC filings do not duplicate during merges.

company_sample <- unique(company_sample, by = "cik_str")

# ------------------------------------------------------------
# 7. Print checks
# ------------------------------------------------------------

message("Number of current S&P 500 rows after removing duplicate CIKs:")
print(nrow(company_sample))

message("Preview:")
print(head(company_sample, 20))

message("Sector counts:")
print(company_sample[, .N, by = gics_sector][order(-N)])

message(
  "NOTE: This is the current S&P 500 list. ",
  "Interpret the project as a current-large-cap firm study, ",
  "not a historically balanced S&P 500 study."
)

# ------------------------------------------------------------
# 8. Save company sample
# ------------------------------------------------------------

fwrite(company_sample, "data/interim/company_sample.csv")

message("Saved S&P 500 company sample to data/interim/company_sample.csv")
