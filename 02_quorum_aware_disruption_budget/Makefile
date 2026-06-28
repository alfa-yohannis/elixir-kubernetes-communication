# Pipeline reproduksi paper 02 (M7). Target utama: `make reproduce` (kecuali RQ7 yang butuh kind).
# Komentar dan dokumentasi kode dalam Bahasa Indonesia; paper dalam Bahasa Inggris.

ELIXIR := MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run
PY     := ~/venv/bin/python

.PHONY: help deps test cluster-test experiments figures paper rq7 reproduce clean

help:            ## Tampilkan target yang tersedia
	@grep -E '^[a-z-]+:.*##' Makefile | sed 's/:.*##/ —/' | sort

deps:            ## Ambil dependensi Elixir
	cd code/app && mix deps.get

test:            ## Tes unit (policy kuorum)
	cd code/app && MIX_ENV=test mix test --exclude cluster

cluster-test:    ## Tes terdistribusi (klaim safety pada cluster peer nyata)
	cd code/app && MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster

experiments:     ## Jalankan eksperimen BEAM -> data/*.csv (RQ1-RQ6)
	cd code/app && $(ELIXIR) harness/run.exs
	cd code/app && MIX_ENV=test mix run harness/policy.exs

figures:         ## Render figur dari data/*.csv -> figures/*.pdf
	$(PY) code/analysis/plot.py

rq7:             ## RQ7: penolakan eviction PDB di cluster kind yang hidup
	bash code/k8s/rq7_eviction.sh

paper:           ## Build paper (XeLaTeX)
	cd paper && latexmk -xelatex -interaction=nonstopmode main.tex

reproduce: deps test experiments figures paper  ## Pipeline penuh (kecuali eksperimen kind RQ7)

clean:           ## Bersihkan build LaTeX
	cd paper && latexmk -C
