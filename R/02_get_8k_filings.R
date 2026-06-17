# ============================================================
# 02_get_8k_filings.R
#
# Purpose:
# Download SEC company submission histories for sample firms,
# including both the recent submissions block and archived
# submissions files listed by the SEC. Keep 8-K and 8-K/A
# filings from 2018 through 2025.
#
# Input:
#   data/interim/company_sample.csv
#
# Output:
#   data/interim/filings_8k.csv
# ============================================================

library(httr2)
library(jsonlite)
library(data.table)
library(stringr)
library(lubridate)

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

# Remove duplicate CIKs just in case the input file contains
# multiple share classes for the same SEC registrant.
company_sample <- unique(company_sample, by = "cik_str")

# ------------------------------------------------------------
# 2. Define sample period
# ------------------------------------------------------------

sample_start <- as.Date("2018-01-01")
sample_end <- as.Date("2025-12-31")

# ------------------------------------------------------------
# 3. SEC request header
# ------------------------------------------------------------
# Use your real name/email. This helps satisfy SEC fair-access
# expectations for automated requests.

sec_user_agent <- "Tim Anderson anderstim@outlook.com"

# ------------------------------------------------------------
# 4. Helper: read one SEC submissions JSON URL
# ------------------------------------------------------------

read_sec_json <- function(url) {
  req <- request(url) |>
    req_headers(`User-Agent` = sec_user_agent)

  resp <- req_perform(req)
  resp_body_json(resp, simplifyVector = TRUE)
}

# ------------------------------------------------------------
# 5. Function to download one company's submissions
# ------------------------------------------------------------
# The company submissions endpoint contains:
#   - json$filings$recent: recent filings
#   - json$filings$files: older archived submission files
#
# Pulling both is safer for a 2018-2025 sample than relying only
# on the "recent" block.

get_company_submissions <- function(cik_10_digit) {

  message("Downloading submissions for CIK: ", cik_10_digit)

  main_url <- paste0(
    "https://data.sec.gov/submissions/CIK",
    cik_10_digit,
    ".json"
  )

  json <- read_sec_json(main_url)

  recent <- as.data.table(json$filings$recent)
  recent[, cik := cik_10_digit]
  recent[, source_file := "recent"]

  archived_list <- list()

  if (!is.null(json$filings$files) && length(json$filings$files) > 0) {

    files_dt <- as.data.table(json$filings$files)

    if ("name" %in% names(files_dt) && nrow(files_dt) > 0) {

      archived_list <- lapply(files_dt$name, function(file_name) {

        archive_url <- paste0(
          "https://data.sec.gov/submissions/",
          file_name
        )

        out <- tryCatch(
          {
            Sys.sleep(0.25)
            archive_json <- read_sec_json(archive_url)
            archive_dt <- as.data.table(archive_json)
            archive_dt[, cik := cik_10_digit]
            archive_dt[, source_file := file_name]
            archive_dt
          },
          error = function(e) {
            message("Failed archived submissions file for CIK: ", cik_10_digit)
            message("Archive file: ", file_name)
            message("Error: ", e$message)
            NULL
          }
        )

        out
      })
    }
  }

  all_company_filings <- rbindlist(
    c(list(recent), archived_list),
    fill = TRUE
  )

  # Remove exact duplicate accession numbers if the same filing
  # appears in more than one SEC block.
  if ("accessionNumber" %in% names(all_company_filings)) {
    all_company_filings <- unique(all_company_filings, by = "accessionNumber")
  }

  return(all_company_filings)
}

# ------------------------------------------------------------
# 6. Download submissions for all sample firms
# ------------------------------------------------------------
# This may take several minutes for the full S&P 500 sample.

all_filings <- rbindlist(
  lapply(company_sample$cik_str, function(cik) {

    out <- tryCatch(
      get_company_submissions(cik),
      error = function(e) {
        message("Failed for CIK: ", cik)
        message("Error: ", e$message)
        NULL
      }
    )

    Sys.sleep(0.25)

    out
  }),
  fill = TRUE
)

# ------------------------------------------------------------
# 7. Attach company information
# ------------------------------------------------------------

all_filings <- merge(
  all_filings,
  company_sample[, .(
    ticker,
    yahoo_ticker,
    title,
    cik_str,
    gics_sector,
    gics_sub_industry
  )],
  by.x = "cik",
  by.y = "cik_str",
  all.x = TRUE
)

# ------------------------------------------------------------
# 8. Keep 8-K and 8-K/A filings
# ------------------------------------------------------------

filings_8k <- all_filings[form %in% c("8-K", "8-K/A")]

# ------------------------------------------------------------
# 9. Clean and filter dates
# ------------------------------------------------------------

filings_8k[, filing_date := as.Date(filingDate)]
filings_8k[, report_date := as.Date(reportDate)]

filings_8k[, acceptance_datetime := ymd_hms(
  acceptanceDateTime,
  tz = "UTC",
  quiet = TRUE
)]

filings_8k <- filings_8k[
  filing_date >= sample_start &
    filing_date <= sample_end
]

# ------------------------------------------------------------
# 10. Keep useful columns
# ------------------------------------------------------------

filings_8k <- filings_8k[, .(
  ticker,
  yahoo_ticker,
  title,
  cik,
  gics_sector,
  gics_sub_industry,
  accessionNumber,
  filing_date,
  report_date,
  acceptance_datetime,
  form,
  items,
  primaryDocument,
  primaryDocDescription,
  size,
  isXBRL,
  source_file
)]

setorder(filings_8k, ticker, filing_date, accessionNumber)

# ------------------------------------------------------------
# 11. Print checks
# ------------------------------------------------------------

message("Number of 8-K / 8-K/A filings from 2018 through 2025:")
print(nrow(filings_8k))

message("Filings by form:")
print(filings_8k[, .N, by = form])

message("Filings by year:")
print(filings_8k[, .N, by = year(filing_date)][order(year)])

message("Top item strings:")
print(filings_8k[, .N, by = items][order(-N)][1:20])

message("Filing source blocks:")
print(filings_8k[, .N, by = source_file][order(-N)][1:20])

# ------------------------------------------------------------
# 12. Save
# ------------------------------------------------------------

fwrite(filings_8k, "data/interim/filings_8k.csv")

message("Saved expanded 8-K filing data to data/interim/filings_8k.csv")
