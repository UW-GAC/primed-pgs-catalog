# primed-pgs-catalog

This repository contains code to fetch data from the PGS catalog and format it 
in data tables in the [PRIMED data model](https://github.com/UW-GAC/primed_data_models).

Load the functions with `source('pgs-catalog-functions.R')`

`pgs_scoring_file_table`: 
- `pgs_id`: id from the PGS Catalog, e.g. "PGS000001"
- `dest_bucket`: google bucket path where the files will be copied to. Do not include a trailing "/"
- `harmonized`; whether to retrieve the scores files harmonized to a reference assembly. Default `TRUE`
- `assembly`: If `harmonized=TRUE`, this controls which files to download. Default `"GRCh38"`

This function fetches data files from the PGS catalog, copies them to a google 
bucket specified by `dest_bucket`, and returns a tibble with a "pgs_scoring_file" table 
containing the bucket paths to the files.

`pgs_model_tables`:
- `pgs_id`: id from the PGS Catalog, e.g. "PGS000001"
- `assembly`: use the same value as supplied to `pgs_scoring_file_table`

This function uses the [quincunx](https://github.com/maialab/quincunx) R package 
to fetch data from the PGS catalog and format it into "pgs_analysis" and
"pgs_sample_devel" data tables. Returns a list with two tibbles.


## primed_fetch_pgs_catalog

This workflow fetches a score from the PGS catalog and imports it to an AnVIL workspace.

input | description
--- | ---
pgs_id | ID in the PGS catalog of the score to fetch, e.g. "PGS000001"
genome_build | `"GRCh38"` or `"GRCh37"`
dest_bucket | google bucket path (starting with "gs://") where scoring files should be written.
model_url | path to the PRIMED data model, e.g. "https://raw.githubusercontent.com/UW-GAC/primed_data_models/refs/heads/pgs/PRIMED_PGS_data_model.json"
workspace_name | A string with the workspace name. e.g, if the workspace URL is https://anvil.terra.bio/#workspaces/fc-product-demo/Terra-Workflows-Quickstart, the workspace name is "Terra-Workflows-Quickstart"
workspace_namespace | A string with the workspace namespace. e.g, if the workspace URL is https://anvil.terra.bio/#workspaces/fc-product-demo/Terra-Workflows-Quickstart, the workspace namespace is "fc-product-demo"
import_tables | A boolean indicating whether tables should be imported to a workspace after validation (default true).
overwrite | A boolean indicating whether existing rows in the data tables should be overwritten (default false).
check_bucket_paths | A boolean indicating whether to check that the files exist in cloud storage (default true).
harmonized | Boolean for whether the score file retrieved should be harmonized (default true)

output | description
--- | ---
validation_report | An HTML file with validation results
tables | A file array with the tables after adding auto-generated columns. This output is not generated if no additional columns are specified in the data model.
md5_check_summary | A string describing the check results
md5_check_details | A TSV file with two columns: file_path of the file in cloud storage and md5_check with the check result.
data_report_summary | A string describing the check results
data_report_details | A TSV file with two columns: file_path of the file in cloud storage validation_report with the path to a text file with validation details


## primed_calc_pgs

This workflow applies a scoring file to a genotype dataset and imports the resulting individual-level scores to an AnVIL workspace. 

Genotype inputs should be an array of VCF files (though a single VCF file with all chromosomes is allowed).

This workflow uses two-stage mean and variance regression-based continuous ancestry adjustment, as described in Khan et al. (2022) [PMID:35710995](https://pubmed.ncbi.nlm.nih.gov/35710995/). The regression is performed in the target genotype data using the provided PC file as input `pcs`. The file format is expected to have a column "IID" with sample ID and PC columns starting with "PC".

input | description
--- | ---
pgs_model_id | ID for the PGS model in the PRIMED data model
scorefile | google bucket path to scoring file
genome_build | `"GRCh38"` or `"GRCh37"`. The scorefile must match the build of the VCF files.
min_overlap | The minimum overlap a score file must have with the genotype data to be scored, expressed as a fraction (e.g. 0.8 for 80% overlap). If the overlap is below this threshold, scoring will not be performed and an error will be raised.
sampleset_name | Name of the sampleset; used to construct output file names.
primed_dataset_id | (optional) If the genotype data corresponds to a PRIMED dataset, provide the PRIMED dataset ID for inclusion in the data table.
vcf | Array of VCF files.
ancestry_adjust | Boolean for whether to adjust scores for ancestry using PCs (if true, provide input "pcs")
pcs | optional file with PCs to adjust for ancestry.
dest_bucket | google bucket path (starting with "gs://") where individual score files should be written
model_url | path to the PRIMED data model, e.g. "https://raw.githubusercontent.com/UW-GAC/primed_data_models/refs/heads/pgs/PRIMED_PGS_data_model.json"
workspace_name | A string with the workspace name. e.g, if the workspace URL is https://anvil.terra.bio/#workspaces/fc-product-demo/Terra-Workflows-Quickstart, the workspace name is "Terra-Workflows-Quickstart"
workspace_namespace | A string with the workspace namespace. e.g, if the workspace URL is https://anvil.terra.bio/#workspaces/fc-product-demo/Terra-Workflows-Quickstart, the workspace namespace is "fc-product-demo"
import_tables | A boolean indicating whether tables should be imported to a workspace after validation (default true).
overwrite | A boolean indicating whether existing rows in the data tables should be overwritten (default false).
check_bucket_paths | A boolean indicating whether to check that the files exist in cloud storage (default true).

output | description
--- | ---
score_file | File with individual-level scores (also included as file_path in pgs_individual_file data table)
adjusted_score_file | File with ancestry-adjusted individual-level scores (also included as file_path in pgs_individual_file data table)
match_summary | Summary file from matching score file variants to genotype data variants (also included as file_readme_path in pgs_individual_file data table)
match_log | Log file from matching score file variants to genotype data variants
variants | File with the variants used for scoring (after matching)
validation_report | An HTML file with validation results
tables | A file array with the tables after adding auto-generated columns. This output is not generated if no additional columns are specified in the data model.
md5_check_summary | A string describing the check results
md5_check_details | A TSV file with two columns: file_path of the file in cloud storage and md5_check with the check result.

