version 1.0 

workflow prepare_variant_file {
    input {
        File scoring_file
        File pvar
        String dataset_name
        String matchout
        
        Int mem_gb
        Int disk_size

    }

    call run_pgs_catalog_match{
        input:
            scoring_file = scoring_file,
            pvar = pvar,
            dataset_name = dataset_name,
            mem_gb = mem_gb,
            disk_size = disk_size
    }

    output{
        File scoring_file_matched = run_pgs_catalog_match.matched_variant_file
        Array[File] log_files = run_pgs_catalog_match.log_files
    }
}

task run_pgs_catalog_match {
  input {
    File scoring_file
    File pvar
    String dataset_name
    
    Int cpu = 2
    Int disk_size
    Int mem_gb
  }

  command <<<
    mkdir -p matchout

    pgscatalog-match --dataset ~{dataset_name} --scorefiles ~{scoring_file} \ 
        --target ~{pvar} --outdir matchout --min_overlap 0.75
  >>>

  output {
    File matched_variant_file = glob("matchout/**/*.scorefile")
    Array[File] log_files = glob("matchout/**/*.log")
  }

  runtime {
    docker: "ghcr.io/pgscatalog/pygscatalog:latest"
    disks: "local-disk ~{disk_size} SSD"
    memory: "~{mem_gb} GB"
    cpu: "~{cpu}"
  }
}