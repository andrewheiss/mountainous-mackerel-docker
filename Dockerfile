# ------------------------------------------------------------------------------
# STAGE 1: Main {renv} image with all packages + Stan
# ------------------------------------------------------------------------------
FROM rocker/tidyverse:4.4.0 AS renv-base

ARG PROJECT="mountainous-mackerel"

# Install system dependencies
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    # Determined by {pak} with ./misc/determine-sysreqs.R
    make pandoc libcurl4-openssl-dev libssl-dev libicu-dev zlib1g-dev libzmq3-dev libxml2-dev libglpk-dev libfontconfig1-dev libfreetype6-dev libpng-dev libfribidi-dev libharfbuzz-dev libjpeg-dev libtiff-dev libgdal-dev gdal-bin libgeos-dev libproj-dev libsqlite3-dev libudunits2-dev \
    # For compiling things
    build-essential \
    clang-3.6 \
    # For downloading things
    curl \
    # For dvisvgm ghostscript-y things
    ghostscript \
    # All done
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure R globally
RUN mkdir -p /usr/local/lib/R/etc/ /usr/lib/R/etc/
RUN echo "options(renv.config.pak.enabled = FALSE, \
    repos = c(CRAN = 'https://cran.rstudio.com/'), \
    download.file.method = 'libcurl', \
    Ncpus = 4)" | tee /usr/local/lib/R/etc/Rprofile.site | tee /usr/lib/R/etc/Rprofile.site

# Copy core {renv} things into the container
RUN mkdir -p /home/rstudio/${PROJECT}/renv/cache && chown rstudio:rstudio /home/rstudio/${PROJECT}
WORKDIR /home/rstudio/${PROJECT}
COPY --chown=rstudio:rstudio ./${PROJECT}/renv.lock renv.lock
RUN echo 'source("renv/activate.R")' >> .Rprofile
COPY --chown=rstudio:rstudio ./${PROJECT}/renv/activate.R renv/activate.R
COPY --chown=rstudio:rstudio ./${PROJECT}/renv/settings.json renv/settings.json

# Change location of {renv} cache to project folder
ENV RENV_WATCHDOG_ENABLED FALSE
ENV RENV_PATHS_CACHE renv/cache

# Install all {renv} packages
RUN R -e 'renv::restore()'
RUN chown -R rstudio:rstudio renv/

# Install cmdstan
RUN mkdir /home/rstudio/.cmdstan
RUN R -e 'cmdstanr::install_cmdstan(dir = "/home/rstudio/.cmdstan", cpp_options = list("CXX" = "clang++"))'
RUN chown -R rstudio:rstudio /home/rstudio/.cmdstan

# Install Quarto
ARG QUARTO_VERSION="1.6.1"
RUN curl -L -o /tmp/quarto-linux-amd64.deb https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb && \
    dpkg -i /tmp/quarto-linux-amd64.deb || true && \
    apt-get install -fy && \
    rm /tmp/quarto-linux-amd64.deb

# Install LaTeX
USER rstudio
RUN Rscript -e 'tinytex::install_tinytex()'
ENV PATH="${PATH}:/home/rstudio/bin"
RUN tlmgr update --all --self
RUN tlmgr install \
    # dvisvgm stuff
    dvisvgm adjustbox collectbox currfile filemod gincltex standalone \
    fp pgf grfext libertine libertinust1math \
    # Quarto + Hikmah template stuff
    nowidow tocloft orcidlink abstract titling tabularray ninecolors \
    enumitem textcase titlesec footmisc caption pdflscape ulem multirow \
    wrapfig colortbl tabu threeparttable threeparttablex environ makecell \
    sidenotes marginnote changepage siunitx mathtools \
    setspace ragged2e fancyhdr pdftex preprint
USER root

# Add fonts
COPY ./misc/fonts/noto-sans/*.ttf /usr/share/fonts/
COPY ./misc/fonts/linux-libertine-o/*.otf /usr/share/fonts/
COPY ./misc/fonts/libertinus-math/*.otf /usr/share/fonts/
RUN fc-cache -f -v


# ------------------------------------------------------------------------------
# STAGE 2: Use the pre-built image for the actual analysis + {targets} pipeline
# ------------------------------------------------------------------------------
FROM renv-base

# This .Rprofile contains commands that force RStudio server to load the
# analysis project by default
COPY --chown=rstudio:rstudio ./misc/Rprofile.R /home/rstudio/.Rprofile

WORKDIR /home/rstudio/${PROJECT}
