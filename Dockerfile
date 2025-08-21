FROM uwgac/anvildatamodels:0.7.0

RUN Rscript -e 'remotes::install_cran("quincunx")'

RUN cd /usr/local && \
    git clone https://github.com/UW-GAC/primed-pgs-catalog.git
