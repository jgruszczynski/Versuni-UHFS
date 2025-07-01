# Check and install needed packages ----
list_of_packages <- c("httr2", "stringr")
packages_to_be_installed <- list_of_packages[!(list_of_packages %in% installed.packages()[,"Package"])]
if(length(packages_to_be_installed)) install.packages(packages_to_be_installed)

library(httr2)
library(stringr)

#load keys----
powerbi.key <- str_replace(read.csv2("/home/jgruszczynski/R-Scripts/!GmailCredentials/powerbi.key",header = F),"Bearer ", "")
#workspace_id <- "861b6777-3aac-4be1-860a-dd57e7476591"
#dataset_id <- "f96f2245-caf2-4807-973b-4aa627feb7b0"

url <- paste0("https://api.apps.estorecheck.com/api/powerbi/refresh-dataset/?",
              "workspace_id=",workspace_id,
              "&dataset_id=",dataset_id)

req <- request(url) %>% 
  req_auth_bearer_token(powerbi.key) %>% 
  req_method("GET")
resp <- req_perform(req)

print("PowerBI refreshed")
