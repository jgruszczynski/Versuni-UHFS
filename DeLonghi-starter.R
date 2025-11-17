rm(list = ls()) 

# Install eSMdb package from github if needed ----
if (!("devtools" %in% installed.packages()[,"Package"])) { 
  install.packages("devtools")
} else {
  if (compareVersion(packageVersion("devtools") |> as.character(), "2.4.5") < 0) {
    install.packages("devtools")
  }
}

if (!("eSMdb" %in% installed.packages()[,"Package"]) |
    compareVersion(packageVersion("eSMdb") |> as.character(), "0.9.7") < 0) { 
  library(devtools)
  git.key <- read.csv("/home/jgruszczynski/R-Scripts/!GmailCredentials/github.key", header = F)[1,1]
  install_github("esm-science-office/RPackages", ref = "main", auth_token = git.key)
}

if (!("pckgver" %in% installed.packages()[,"Package"]) | compareVersion(packageVersion("eSMdb") |> as.character(), "0.1.0") < 0 ) { 
  library(devtools)
  git.key <- read.csv("/home/jgruszczynski/R-Scripts/!GmailCredentials/github.key", header = F)[1,1]
  install_github("https://github.com/esm-science-office/pckgver", ref = "main", auth_token = git.key)
}

# Load packages ----
# Internal db package 
library(pckgver)
library(eSMdb)

# Data manipulation
pckgver::install_or_update_package("dplyr","1.1.4")
library(dplyr)
pckgver::install_or_update_package("tidyr", "1.3.1")
library(tidyr)
pckgver::install_or_update_package("lubridate", "1.9.3")
library(lubridate)
pckgver::install_or_update_package("stringr", "1.5.1")
library(stringr)

# Data dumping
pckgver::install_or_update_package("AzureStor", "3.7.0")
library(AzureStor)   

# Google packages
pckgver::install_or_update_package("googleAuthR", "2.0.2")
library(googleAuthR)
pckgver::install_or_update_package("googlesheets4", "1.1.1")
library(googlesheets4)
pckgver::install_or_update_package("googledrive", "2.1.1")
library(googledrive)

# Excel hanlder 
pckgver::install_or_update_package("openxlsx", "4.2.7")
library(openxlsx)

# Parquet handler 
pckgver::install_or_update_package("arrow", "17.0.0.1")
library(arrow)

# Other helpers 
pckgver::install_or_update_package("tictoc", "1.2.1")
library(tictoc)

# Authorisations ----
## Google authorization ----
token <- gargle::credentials_service_account(
  scopes = c(
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/gmail.send"
  ),
  path = "/home/jgruszczynski/R-Scripts/!GmailCredentials/r-shiny-apps-1-7bbb0e0a4c24.json",
  subject = "science@estoremedia.com"
)

drive_auth(token = token)
gs4_auth(token = token)

# Azure Authorization ----
AzureKey <- as.character(read.csv("/home/jgruszczynski/R-Scripts/!GmailCredentials/BlobVersuniUHFS.key",header = F)[1])
bl_endp_key <- storage_endpoint("https://versuniuhfs.blob.core.windows.net", key = AzureKey)
AzureContainer <- storage_container(bl_endp_key,"uhfs-delonghi")

# Main Loop ----
folder <- "/home/jgruszczynski/R-Scripts/Versuni-UHFS"
setwd(folder)

d1 <- as.Date("2025-11-12", origin = "1970-01-01")
d2 <- as.Date("2025-11-13", origin = "1970-01-01")

dates <- seq.Date(d1, d2, by = "day")


for (d in dates) {
  project_id <- 3781       
  clust <- 1
  
  date <- as.Date(d, origin = "1970-01-01")
  print(date)
  
  source("Versuni-UHFS.R")
}