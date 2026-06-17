# ============================================================
# 03_parse_8k_items.R
#
# Purpose:
# Parse the SEC 8-K "items" field into one row per filing-item
# combination and classify each item into an event category.
#
# Input:
#   data/interim/filings_8k.csv
#
# Output:
#   data/interim/filing_items.csv
# ============================================================

library(data.table)
library(stringr)
library(lubridate)

# ------------------------------------------------------------
# 0. Create output folder
# ------------------------------------------------------------

dir.create("data/interim", recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# 1. Read the 8-K filings created in Step 2
# ------------------------------------------------------------

filings_8k <- fread(
  "data/interim/filings_8k.csv",
  colClasses = list(
    character = c(
      "ticker",
      "yahoo_ticker",
      "title",
      "cik",
      "accessionNumber",
      "form",
      "items",
      "primaryDocument",
      "primaryDocDescription"
    )
  )
)

# Make sure CIKs stay as 10-digit character strings
filings_8k[, cik := str_pad(
  cik,
  width = 10,
  side = "left",
  pad = "0"
)]

# Make sure dates are actually dates
filings_8k[, filing_date := as.Date(filing_date)]
filings_8k[, report_date := as.Date(report_date)]
filings_8k[, acceptance_datetime := ymd_hms(
  acceptance_datetime,
  tz = "UTC",
  quiet = TRUE
)]

# ------------------------------------------------------------
# 2. Clean the raw SEC item-code field
# ------------------------------------------------------------

# The items column can look like:
# "2.02,9.01"
# "5.02,9.01"
# "1.01,2.03,9.01"
#
# We remove spaces so the item codes are easier to split.

filings_8k[, items_clean := str_replace_all(items, "\\s+", "")]

# ------------------------------------------------------------
# 3. Remove filings with missing item codes
# ------------------------------------------------------------

filings_with_items <- filings_8k[
  !is.na(items_clean) &
    items_clean != ""
]

# ------------------------------------------------------------
# 4. Split item codes so there is one row per filing-item pair
# ------------------------------------------------------------

filing_items <- filings_with_items[
  ,
  .(
    item = unlist(str_split(items_clean, ","))
  ),
  by = .(
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
    primaryDocument,
    primaryDocDescription
  )
]

# ------------------------------------------------------------
# 5. Clean item codes
# ------------------------------------------------------------

filing_items[, item := as.character(item)]
filing_items[, item := str_trim(item)]
filing_items[, cik := as.character(cik)]

# Keep only item codes that look like 8-K item codes, for example:
# 1.01, 2.02, 5.02, 8.01, 9.01

filing_items <- filing_items[
  str_detect(item, "^[0-9]+\\.[0-9]+$")
]

# ------------------------------------------------------------
# 6. Classify item codes into readable event groups
# ------------------------------------------------------------

filing_items[
  ,
  item_group := fifelse(
    item == "1.01",
    "material_agreement",
    fifelse(
      item == "1.02",
      "termination_of_material_agreement",
      fifelse(
        item == "2.01",
        "merger_acquisition_asset_sale",
        fifelse(
          item == "2.02",
          "earnings_or_results",
          fifelse(
            item == "2.03",
            "debt_or_financing_obligation",
            fifelse(
              item == "5.02",
              "leadership_change",
              fifelse(
                item == "8.01",
                "other_events",
                fifelse(
                  item == "9.01",
                  "financial_statements_or_exhibits",
                  "other"
                )
              )
            )
          )
        )
      )
    )
  )
]

# ------------------------------------------------------------
# 7. Create broader categories for easier analysis
# ------------------------------------------------------------

filing_items[
  ,
  broad_group := fifelse(
    item_group == "earnings_or_results",
    "earnings",
    fifelse(
      item_group == "leadership_change",
      "leadership",
      fifelse(
        item_group %in% c(
          "material_agreement",
          "termination_of_material_agreement",
          "merger_acquisition_asset_sale",
          "debt_or_financing_obligation"
        ),
        "corporate_transaction",
        fifelse(
          item_group == "financial_statements_or_exhibits",
          "exhibits",
          "other"
        )
      )
    )
  )
]

# ------------------------------------------------------------
# 8. Add an item priority for filing-level analysis
# ------------------------------------------------------------
# Some 8-K filings contain several item codes. This priority lets
# later scripts create a "primary item" dataset with one row per
# accession number, while still preserving the full filing-item
# dataset here.

filing_items[, item_priority := fifelse(item == "2.02", 1,
                                 fifelse(item == "2.01", 2,
                                 fifelse(item == "1.01", 3,
                                 fifelse(item == "1.02", 4,
                                 fifelse(item == "2.03", 5,
                                 fifelse(item == "5.02", 6,
                                 fifelse(item == "8.01", 7,
                                 fifelse(item == "9.01", 98, 99))))))))]

# ------------------------------------------------------------
# 9. Keep useful columns
# ------------------------------------------------------------

filing_items <- filing_items[, .(
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
  primaryDocument,
  primaryDocDescription,
  item,
  item_group,
  broad_group,
  item_priority
)]

# ------------------------------------------------------------
# 10. Print summaries
# ------------------------------------------------------------

message("Number of filing-item rows:")
print(nrow(filing_items))

message("Number of unique filing accession numbers:")
print(uniqueN(filing_items$accessionNumber))

message("Item-code counts:")
print(filing_items[, .N, by = item][order(-N)])

message("Item-group counts:")
print(filing_items[, .N, by = item_group][order(-N)])

message("Broad-group counts:")
print(filing_items[, .N, by = broad_group][order(-N)])

# ------------------------------------------------------------
# 11. Save parsed filing-item dataset
# ------------------------------------------------------------

fwrite(filing_items, "data/interim/filing_items.csv")

message("Saved parsed filing items to data/interim/filing_items.csv")
