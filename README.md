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
dest_bucket | google bucket path (starting with "gs://") where scoring files should be written
model_url | path to the PRIMED data model, e.g. "https://raw.githubusercontent.com/UW-GAC/primed_data_models/refs/heads/pgs/PRIMED_PGS_data_model.json"
pgs_id | ID in the PGS catalog of the score to fetch, e.g. "PGS000001"
workspace_name | A string with the workspace name. e.g, if the workspace URL is https://anvil.terra.bio/#workspaces/fc-product-demo/Terra-Workflows-Quickstart, the workspace name is "Terra-Workflows-Quickstart"
workspace_namespace | A string with the workspace name. e.g, if the workspace URL is https://anvil.terra.bio/#workspaces/fc-product-demo/Terra-Workflows-Quickstart, the workspace namespace is "fc-product-demo"
assembly | The genome assembly, either "GRCh38" (default) or "GRCh37"
harmonized | Boolean for whether the score file retrieved should be harmonized (default true)
import_tables | A boolean indicating whether tables should be imported to a workspace after validation.
overwrite | A boolean indicating whether existing rows in the data tables should be overwritten.

output | description
--- | ---
validation_report | An HTML file with validation results
tables | A file array with the tables after adding auto-generated columns. This output is not generated if no additional columns are specified in the data model.
md5_check_summary | A string describing the check results
md5_check_details | A TSV file with two columns: file_path of the file in cloud storage and md5_check with the check result.
data_report_summary | A string describing the check results
data_report_details | A TSV file with two columns: file_path of the file in cloud storage validation_report with the path to a text file with validation details


## primed_pgsc_calc

This workflow applies a scoring file to a genotype dataset and imports the resulting individual-level scores to an AnVIL workspace. It uses the [pgsc_calc](https://pgsc-calc.readthedocs.io/) software to compute scores. **If an input is not specified in the table below (e.g. ancestry_ref_panel, pgs_id), it should be left blank when running the workflow.**

Genotype inputs may be either an array of VCF files (in which case they are converted to pgen/psam/pvar prior to running pgsc_calc), or pgen/psam/pvar files. **If pgen/psam/pvar are provided; the pvar file should have variant ids in the form chr:pos:ref:alt without the "chr" prefix.**

If the scoring file does not have a header as specified in the [pgsc_calc documentation](https://pgsc-calc.readthedocs.io/en/latest/how-to/calculate_custom.html), a header will be added prior to running pgsc_calc.

**Note that including an underscore in the "sampleset" argument will cause the workflow to fail.**

input | description
--- | ---
model_url | path to the PRIMED data model, e.g. "https://raw.githubusercontent.com/UW-GAC/primed_data_models/refs/heads/pgs/PRIMED_PGS_data_model.json"
pgs_model_id | ID for the PGS model in the PRIMED data model
scorefile | google bucket path to scoring file
workspace_name | A string with the workspace name. e.g, if the workspace URL is https://anvil.terra.bio/#workspaces/fc-product-demo/Terra-Workflows-Quickstart, the workspace name is "Terra-Workflows-Quickstart"
workspace_namespace | A string with the workspace name. e.g, if the workspace URL is https://anvil.terra.bio/#workspaces/fc-product-demo/Terra-Workflows-Quickstart, the workspace namespace is "fc-product-demo"
arguments | [Additional arguments](https://pgsc-calc.readthedocs.io/en/latest/reference/params.html#param-ref) to pass to psgc_calc, e.g. `[ "--min_overlap 0.5" ]`
chromosome | Array of chromosome strings (1-22, X, Y) corresponding to `vcf` or `pgen/pvar/psam`. If there is one file with multiple chromosomes, this input should be an empty string (`[""]`)
pgen | Array of pgen files
pvar | Array of pvar files
psam | Array of psam files
sampleset_name | Name of the sampleset; used to construct output file names (default `"cohort"`). **Underscores are not allowed**
target_build | `"GRCh38"` (default) or `"GRCh37"`
vcf | Array of VCF files. If provided, will be converted to pgen/pvar/psam. If not provided, use pgen/pvar/psam inputs instead.
import_tables | A boolean indicating whether tables should be imported to a workspace after validation.
overwrite | A boolean indicating whether existing rows in the data tables should be overwritten.

output | description
--- | ---
score_file | File with individual-level scores (also included as file_path in pgs_individual_file data table)
report_file | File with QC report (also included as file_readme_path in pgs_individual_file data table)
validation_report | An HTML file with validation results
tables | A file array with the tables after adding auto-generated columns. This output is not generated if no additional columns are specified in the data model.
md5_check_summary | A string describing the check results
md5_check_details | A TSV file with two columns: file_path of the file in cloud storage and md5_check with the check result.
