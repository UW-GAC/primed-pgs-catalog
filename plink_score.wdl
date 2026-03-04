version 1.0

import "primed_calc_pgs.wdl" as tasks

workflow plink_score {
    input {
        File pgen
        File pvar
        File psam
        File scorefile
        String sampleset_name
    }

    call tasks.plink_score {
        input:
            scorefile = scorefile,
            pgen = pgen,
            pvar = pvar,
            psam = psam,
            prefix = sampleset_name
    }

    output {
        File score_file = plink_score.scores
        File variants = plink_score.variants
    }

     meta {
          author: "Stephanie Gogarten"
          email: "sdmorris@uw.edu"
     }
}
