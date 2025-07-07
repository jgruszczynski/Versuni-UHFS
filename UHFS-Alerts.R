# Packages ----
suppressMessages(pckgver::install_or_update_package("emayili","0.9.1"))
library(emayili)
suppressMessages(pckgver::install_or_update_package("glue", "1.7.0"))
library(glue)
suppressMessages(pckgver::install_or_update_package("knitr", "1.4.8"))
library(glue)
suppressMessages(pckgver::install_or_update_package("kableExtra", "1.4.0"))
library(kableExtra)
suppressMessages(pckgver::install_or_update_package("openxlsx", "4.2.8"))
library(openxlsx)

# Configuration email ----
lines <- readLines("/home/jgruszczynski/R-Scripts/!GmailCredentials/estorecheck_reports_mail.key")
esv_host <- trimws(gsub('"', '',strsplit(lines[1], ":")[[1]][2]))
esv_username <- trimws(gsub('"', '',strsplit(lines[2], ":")[[1]][2]))
esv_password <- trimws(gsub('"', '',strsplit(lines[3], ":")[[1]][2]))

# Set up SMTP server
smtp <- server(
  host = esv_host,
  port = 587,       
  username = esv_username,
  password = esv_password,      
  reuse = FALSE
)

# Read emails
emails <- read.csv2("emails.csv", header = F) |>
  pull(V1)

# Functions ----
clear_store <- function(url) {
  url <- gsub("^https?://", "", url)     # remove http:// or https://
  url <- gsub("^www\\.", "", url)        # remove www.
  url <- gsub("/$", "", url)             # remove trailing /
  url
}

format_price <- function(x) {
  ifelse(is.na(x), "",
         formatC(x, format = "f", big.mark = " ", digits = 2))
}

# Constants ----
alerts_file <- 'alerts_db.txt' 

# 0.0 Init ----
if (!file.exists(alerts_file)) {
  file.create(alerts_file)
}
alerts_db <- readLines(alerts_file)


# 1.0 Data preparation ----
fds_cl <- fds |>
  mutate(scan_ml_probe_datetime = update(scan_ml_probe_datetime, seconds = 0)) |>
  mutate(shop_url = clear_store(shop_url))

last_probes <- fds_cl |>
  distinct(project_id, scan_ml_probe_datetime, scan_ml_probe_id) |>
  group_by(project_id) |>
  arrange(desc(scan_ml_probe_datetime)) |>
  slice_head(n = 2) 

last_probe_id <- fds_cl |>
  filter(scan_ml_probe_id %in% last_probes$scan_ml_probe_id) |>
  select(project_id, scan_ml_probe_datetime, scan_ml_probe_id) |>
  unique() |>
  arrange(desc(scan_ml_probe_datetime)) |>
  group_by(project_id) |>
  slice_head(n = 1) 

new_probes_to_alert <- last_probe_id |>
  ungroup() |>
  select(scan_ml_probe_id) |>
  filter(!(scan_ml_probe_id %in% alerts_db))
 
if (nrow(new_probes_to_alert) > 0) {
    alerts_fds <- fds_cl |>
      filter(scan_ml_probe_id %in% new_probes_to_alert$scan_ml_probe_id) |>
      filter(scan_ml_probe_id %in% last_probes$scan_ml_probe_id) |>
      select(project_product_id, shop_url, scan_ml_probe_datetime, scan_ml_product_price) |>
      arrange(project_product_id, shop_url , desc(scan_ml_probe_datetime)) |>
      group_by(shop_url, project_product_id) |>
      mutate(price_type = if_else(row_number() == 1, "current_price", "previous_price")) %>%
      ungroup() |>
      select(project_product_id, shop_url, price_type, scan_ml_product_price) |>
      pivot_wider(names_from = price_type, values_from = scan_ml_product_price) |>
      mutate(
        price_trend = case_when(
          coalesce(current_price, 0) > coalesce(previous_price, 0) ~ "Up",
          coalesce(current_price, 0) < coalesce(previous_price, 0) ~ "Down",
          TRUE ~ "same"
        )
      ) |>
      filter(price_trend != "same") |>
      filter(!is.na(current_price)) |>
      filter(!is.na(previous_price))
    
    sellers <- fds_cl |>
      filter(scan_ml_probe_id %in% new_probes_to_alert$scan_ml_probe_id) |>
      filter(scan_ml_probe_id %in% last_probe_id$scan_ml_probe_id) |>
      select(project_product_id, shop_url, scan_ml_product_seller_name) |>
      unique() 
    
    alerts_fds <- alerts_fds |>
      inner_join(sellers)
    
    prod_names <- ml |>
      mutate(product_name = paste(project_product_producer, 
                                  project_product_model, 
                                  if_else(is.na(project_product_attr1),"",project_product_attr1), 
                                  if_else(is.na(project_product_attr2),"",project_product_attr2), 
                                  if_else(is.na(project_product_attr3),"",project_product_attr3), 
                                  sep = " ")) |>
      mutate(product_name = str_squish(product_name)) |>
      select(project_product_id, product_name, project_product_code1)
    
    alerts_fds <- alerts_fds |>
      left_join(prod_names, by = "project_product_id") |>
      select(-project_product_id) |>
      arrange(shop_url, product_name)
    
    # 2.0 Notification composition ----
    #first_date <- last_probes[1]
    #last_date <- last_probes[2]
    
    if (nrow(alerts_fds) > 0) {
      ## 2.1 Table ----
      html_table <- alerts_fds |>
        mutate( 
          current_price = format_price(current_price),
          previous_price = format_price(previous_price)
        ) |>
        mutate(price_trend = case_when(
          price_trend == "Up" ~ '<span style="color:green;">▲</span>',
          price_trend == "Down" ~ '<span style="color:red;">▼</span>',
          TRUE ~ ""
        )) |>
        select(product_name, project_product_code1, shop_url, scan_ml_product_seller_name, current_price, previous_price, price_trend) |>
        kable("html", 
              escape = FALSE, 
              align = c("l", "l", "l", "l", "r", "r", "c"), 
              col.names = c("Product Name", "ASIN", "Store", "Seller", "Current Price", "Previous Price", "Trend")
              ) |>
        kable_styling("striped", full_width = FALSE, position = "left", font_size = 11) |>
        row_spec(0, bold = TRUE, background = "#f2f2f2") %>%
        column_spec(1, width = "8cm", extra_css = "word-wrap: break-word; white-space: normal;") |>  # Wrap product name
        column_spec(1:7, extra_css = "line-height: 1.1; padding-top: 2px; padding-bottom: 2px;")
      
      ## 2.2 xlsx ----
      ### 2.2.1  Data ---- 
      xlsx_data <- alerts_fds %>%
        mutate(
          current_price = round(current_price, 2),
          previous_price = round(previous_price, 2),
          trend_arrow = case_when(
            price_trend == "Up" ~ "▲",
            price_trend == "Down" ~ "▼",
            TRUE ~ ""
          )
        ) %>%
        select(product_name, project_product_code1, shop_url, scan_ml_product_seller_name, current_price, previous_price, trend_arrow) |>
        rename(`Product Name` = product_name,
               `ASIN` = project_product_code1, 
               `Store` = shop_url, 
               `Seller` = scan_ml_product_seller_name, 
               `Current Price` = current_price, 
               `Previous Price` = previous_price,
               `Trend` = trend_arrow)
      
      ### 2.2.2. Create a workbook and add a worksheet ----
      wb <- createWorkbook()
      addWorksheet(wb, "Price Changes")
      
      report_title <- glue("UHFS tool: Price changes summary")
      
      ### 2.2.3. Define styles ----
      header_style <- createStyle(textDecoration = "bold", halign = "center", fgFill = "#f2f2f2")
      price_style <- createStyle(numFmt = "# ##0.00", halign = "right")
      arrow_style_up <- createStyle(fontColour = "#00B050", halign = "center")   # green
      arrow_style_down <- createStyle(fontColour = "#C00000", halign = "center") # red
      title_style <- createStyle(fontSize = 16, textDecoration = "bold", halign = "left", valign = "center")
      
      ### 2.2.4. Write data ----
      writeData(wb, "Price Changes", report_title, startRow = 1, startCol = 1, colNames = FALSE)
      writeData(wb, "Price Changes", xlsx_data, startRow = 2, headerStyle = header_style)
      
      ### 2.2.5. Apply styles ----
      addStyle(wb, "Price Changes", title_style, rows = 1, cols = 1, gridExpand = TRUE)
      addStyle(wb, "Price Changes", style = price_style, rows = 3:(nrow(xlsx_data) + 2), cols = 5:6, gridExpand = TRUE)
      freezePane(wb, sheet = "Price Changes", firstActiveRow = 3)
      
      for (i in seq_len(nrow(xlsx_data))) {
        arrow <- xlsx_data$Trend[i]
        if (arrow == "▲") {
          addStyle(wb, "Price Changes", style = arrow_style_up, rows = i + 2, cols = 7)
        } else if (arrow == "▼") {
          addStyle(wb, "Price Changes", style = arrow_style_down, rows = i + 2, cols = 7)
        }
      }
      
      ### 2.2.6. Set column widths and wrap product names if needed ----
      setColWidths(wb, "Price Changes", cols = 1, widths = 60)  # wide first column
      setColWidths(wb, "Price Changes", cols = 2:7, widths = "auto")
      setColWidths(wb, "Price Changes", cols = 2, widths = 12)
      setColWidths(wb, "Price Changes", cols = 3, widths = 13)
      setColWidths(wb, "Price Changes", cols = 4, widths = 12)
      
      ### 2.2.7. Save the file ----
      saveWorkbook(wb, "uhfs_notification.xlsx", overwrite = TRUE)
      
      ## 2.3 Summary ----
      summary_counts <- alerts_fds |>
        count(shop_url, name = "changes") |>
        arrange(desc(changes))
      
      store_breakdown <- paste0(summary_counts$shop_url, ": ", summary_counts$changes, collapse = "<br>")
      
      summary_text <- glue(
        "We found {nrow(alerts_fds)} price changes across stores.<br>",
        "Breakdown by store:<br> {store_breakdown}.<br><br>"
      )
      
      ## 2.4 Full email body ----
      email_body <- glue('
      <p>Dear Recipient,</p>
      
      <p>This is an automated price change notification from the <strong>UHFS tool</strong>.</p>
      
      <p>{summary_text}</p>
      
      {html_table}
      
      <p>Best regards,<br>
      eStoreBrands Team</p>
      
      <hr>
      <p><em>P.S. This email was sent automatically. Please do not reply to it.</em></p>
      ')
      
      ## 2.5 Build the email ----
      email <- emayili::envelope() |>
        emayili::from('UHFS Reports <reports@estorecheck.com>') |>
        emayili::to(emails) |>
        #emayili::cc(mail_cc) |>
        emayili::bcc("jakub.gruszczynski@estoremedia.com") |>
        emayili::subject(glue("Notification from the UHFS tool")) |>
        emayili::html(email_body) |>
        emayili::attachment(paste0(folder,"/","uhfs_notification.xlsx"))
      
      ## 2.6 Send ----
        smtp(email, verbose = FALSE)
    }
    
    ## 3.0 Add probe id to the tracker ----
    cat(last_probe_id$scan_ml_probe_id, file = 'alerts_db.txt', append = TRUE, sep = "\n")
    print(paste0('Alerts for probe ', last_probe_id , ' sent'))
} else {
  print(paste0('Alerts for probe ', last_probe_id , ' was already sent'))
}
 