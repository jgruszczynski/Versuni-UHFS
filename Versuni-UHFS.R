# Options  ----
options(dplyr.summarise.inform = FALSE)
options(azure_storage_progress_bar = FALSE)

# Queries ----
ml_query <- function(project_id) {
  paste0("
    SELECT
      pp.project_id,
    	pp.project_product_id,
    	pp.project_product_category_id,
    	pp.project_product_producer,
    	pp.project_product_model,
    	pp.project_product_attr1,
    	pp.project_product_attr2,
    	pp.project_product_attr3,
    	pp.project_product_attr4,
    	pp.project_product_attr5,
    	pp.project_product_code1,
    	pp.project_product_code2,
    	pp.project_product_code3
    FROM
    	project_products pp
    WHERE
    	1=1
    	AND pp.project_id IN (",project_id,")
  ")
}
hfs_probes_query <- function(project_id,date) {
  paste0("
    SELECT
    	smp.scan_ml_probe_id,
    	smp.project_id,
    	scan_ml_probe_date AS scan_ml_probe_datetime,
    	DATE(scan_ml_probe_date) AS scan_ml_probe_date
    FROM
    	scan_ml_probes smp
    		LEFT JOIN 
    		(
    		SELECT 
					s.project_id,
					s.scan_ml_probe_id,
					COUNT(1) AS `errors`
				FROM 
					scan_ml_products s
				WHERE 
					1=1 
					AND s.project_id IN (",project_id,")
					AND s.scan_ml_card_status = 3 AND s.scan_ml_card_error = 1
			    	AND (DATE(s.scan_ml_probe_date) = '",date,"' OR DATE(s.scan_ml_probe_date) = '",date - 1,"')
				GROUP BY
					s.project_id,
					s.scan_ml_probe_id
			) err
			ON err.project_id = smp.project_id AND err.scan_ml_probe_id = smp.scan_ml_probe_id
    WHERE
    	1=1
    	AND smp.project_id IN (",project_id,")
    	AND isnull(err.errors)
    	AND (DATE(smp.scan_ml_probe_date) = '",date,"' OR DATE(smp.scan_ml_probe_date) = '",date - 1,"')
         ")
}
hfs_data_query <- function(probe_id) {
  paste0("
    SELECT
      smp.scan_ml_product_id,
    	smp.scan_ml_probe_id,
    	smp.project_product_id,
    	smp.project_id,
    	smp.scan_ml_probe_date,
    	smp.shop_url,
    	smp.scan_ml_product_price,
    	smp.scan_ml_product_price_old,
    	smp.scan_ml_product_available,
    	smp.scan_ml_product_3thparty,
    	smp.scan_ml_product_buybox_win,
    	smp.scan_ml_product_buybox_price,
    	smp.scan_ml_product_seller_name
    FROM
    	scan_ml_products smp
    WHERE
    	1=1 
    	AND smp.scan_ml_probe_id = ",probe_id,"
    	AND smp.scan_ml_card_status = 3          
         ")
}

# Constants ----
# project_id <- 1181
# clust <- 1

# 1.0 Main ----
setwd(folder)

# 2.0 Get Data From eSMdb ----
ml <- eSMdb::dump_clust(i = clust, query = ml_query(project_id = project_id)) |>
  as_tibble()
hfs_probes <- eSMdb::dump_clust(i = clust, query = hfs_probes_query(project_id = project_id, date = date)) |>
  as_tibble()

hfs_probes_ids <- hfs_probes |>
  pull(scan_ml_probe_id)

hfs_data <- c()
for (probe_id in hfs_probes_ids) {
  hfs_data_probe <- eSMdb::dump_clust(i = clust, query = hfs_data_query(probe_id = probe_id)) |>
    as_tibble()
  hfs_data <- bind_rows(hfs_data, hfs_data_probe)
}

# 3.0 Final data set ----
fds <- hfs_data |>
  inner_join(hfs_probes, by = c("scan_ml_probe_id" = "scan_ml_probe_id",
                                "project_id" = "project_id",
                                "scan_ml_probe_date" = "scan_ml_probe_date"))

# This is to remove doubles 
fds <- fds |>
  group_by(project_product_id, shop_url, scan_ml_probe_id) |>
  mutate(N = n()) |>
  group_by(project_product_id, shop_url, scan_ml_probe_id, N) |>
  group_modify(~ {
    if (nrow(.x) == 1) {
      return(.x)
    } else {
      available <- .x |> filter(scan_ml_product_available  == 1)
      if (nrow(available) > 0) {
        return(slice_min(available, scan_ml_product_price, with_ties = FALSE))
      } else {
        return(slice_min(.x, scan_ml_product_price, with_ties = FALSE))
      }
    }
  }) |>
  ungroup() |>
  select(-N)

data_days <- fds |>
  pull(scan_ml_probe_date) |>
  unique()

for (d in data_days) {
  d <- as.Date(d, origin = "1970-01-01")
  #print(d)
  fds1 <- fds |>
    filter(scan_ml_probe_date == d)

  write_parquet(x = fds1, sink = paste0(project_id, "_fds_",as.Date(d, origin = "1970-01-01"),".parquet"), compression = "snappy")
}
write_parquet(x = ml, sink = paste0(project_id, "_ml.parquet"), compression = "snappy")

# 4.0 Upload and clear ----
files <- dir(pattern = ".parquet", full.names = T, recursive = T)
if (length(files) > 0) {
  storage_multiupload(AzureContainer, files, substr(files,3,5000))
}
unlink(files)
