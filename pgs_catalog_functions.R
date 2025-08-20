library(quincunx)
library(AnVIL)
library(AnVILGCP)
library(tidyverse)

pgs_file_table <- function(pgs_id, dest_bucket, harmonized=TRUE, assembly="GRCh38") {
  pgs_path <- file.path("https://ftp.ebi.ac.uk/pub/databases/spot/pgs/scores", pgs_id, "ScoringFiles")
  if (harmonized) {
    pgs_path <- file.path(pgs_path, "Harmonized")
    pgs_file <- paste0(pgs_id, "_hmPOS_", assembly, ".txt.gz")
  } else {
    pgs_file <- paste0(pgs_id, ".txt.gz")
  }
  pgs_path <- file.path(pgs_path, pgs_file)
  download.file(pgs_path, pgs_file, method="wget")
  bucket_path <- file.path(dest_bucket, pgs_file)
  md5 <- read_delim(paste0(pgs_path, ".md5"), col_names="md5", col_types="c-")$md5
  dat <- read_tsv(pgs_file, comment="#")
  if (harmonized) {
    dat <- dat %>%
      mutate(rsID = hm_rsID, chr_name = hm_chr, chr_position = hm_pos) %>%
      select(-hm_rsID, -hm_chr, -hm_pos)
    write_tsv(dat, pgs_file)
    md5 <- tools::md5sum(pgs_file)
  }
  pgs_file_table <- tibble(
    pgs_analysis_id = pgs_id,
    md5sum = md5,
    file_path = bucket_path,
    file_type = "data",
    chromosome = "ALL",
    n_variants = nrow(dat)
  )
  avcopy(pgs_file, bucket_path)
  return(pgs_file_table)
}

population_descriptors <- function(x) {
  tmp <- x %>%
    select(pgs_id, sample_id, starts_with("ancestry")) %>%
    select(!where(anyNA))
  descriptors <- setdiff(names(tmp), c("pgs_id", "sample_id"))
  tmp2 <- x %>%
    mutate(countries_of_recruitment = str_replace_all(country, ",", "|")) %>%
    select(pgs_id, sample_id, countries_of_recruitment)
  tmp %>%
    unite(col="population_labels", -ends_with("id"), sep=" | ") %>%
    mutate(population_descriptor = paste(descriptors, collapse = " | ")) %>%
    left_join(tmp2)
}

cohorts <- function(x) {
  if (nrow(x) == 0) {
    return(tibble(pgs_id=character(), sample_id=integer(), cohorts=character()))
  }
  x %>%
    select(pgs_id, sample_id, cohort_symbol) %>%
    mutate(num=row_number()) %>%
    pivot_wider(values_from=cohort_symbol, names_from=num, names_prefix="cohort") %>%
    unite(col="cohorts", starts_with("cohort"), sep="|", na.rm=TRUE)
}

# supply assembly instead of reading from the data, so we can get harmonized score files
pgs_analysis_tables <- function(pgs_id, assembly) {
  scores <- get_scores(pgs_id)
  
  sample_table <- scores@samples %>%
    mutate(
      proportion_male = sample_percent_male / 100,
    ) %>%
    select(
      pgs_id,
      sample_id,
      stage,
      n_samp = sample_size,
      n_case = sample_cases,
      n_ctrl = sample_controls,
      proportion_male
    ) %>%
    mutate(
      pgs_analysis_id = pgs_id,
      pgs_sample_name = paste(pgs_id, sample_id, sep="_"),
    ) %>%
    left_join(population_descriptors(scores@samples)) %>%
    left_join(cohorts(scores@cohorts)) %>%
    select(-pgs_id, -sample_id)
  
  analysis_table <- scores@scores %>%
    mutate(pgs_analysis_id = pgs_id) %>%
    select(
      pgs_analysis_id,
      pgsc_pgs_id = pgs_id,
      pgs_name = pgs_name,
      n_variants,
      n_variant_interactions = n_variants_interactions,
      reported_trait,
      pgs_development_method = pgs_method_name,
      pgs_development_details = pgs_method_params
    ) %>%
    mutate(
      pgs_source = "PGS Catalog",
      pgs_source_url = paste0("https://www.pgscatalog.org/score/", pgsc_pgs_id),
      pubmed_id = scores@publications$pubmed_id,
      doi = scores@publications$doi,
      title = scores@publications$title,
      first_author = scores@publications$author_fullname,
      journal = scores@publications$publication,
      publication_date = scores@publications$publication_date,
      pgsc_pgp_id = scores@publications$pgp_id,
      reference_assembly = assembly,
      mapped_trait = scores@traits$trait,
      trait_identifier = scores@traits$efo_id,
      trait_description = scores@traits$description
      )
  
  list(pgs_analysis = analysis_table,
       pgs_sample_devel = sample_table)
}

