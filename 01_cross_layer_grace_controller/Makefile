# Reproduksi satu-perintah untuk artefak grace-convergence controller.
# Jalankan dari root proyek (folder yang memuat code/, paper/, data/, figures/).
# Catatan: JANGAN pernah `pkill -f '...@127.0.0.1'` di sekitar eksperimen (mematikan shell, exit 144).

ELIXIR := MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run
PY     := ~/venv/bin/python

.PHONY: help deps test cluster-test experiments figures paper reproduce clean

help:            ## Tampilkan daftar target
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-14s %s\n", $$1, $$2}'

deps:            ## Pasang dependensi (Elixir + Python)
	cd code/app && mix deps.get
	$(PY) -m pip install -r code/analysis/requirements.txt

test:            ## Unit test (policy grace + Probe/EWMA + property)
	cd code/app && mix test

cluster-test:    ## Integration test cluster BEAM 2-node (:peer)
	cd code/app && MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster

experiments:     ## Jalankan semua eksperimen BEAM -> data/*.csv
	cd code/app && $(ELIXIR) harness/run.exs
	cd code/app && $(ELIXIR) harness/sweep.exs
	cd code/app && $(ELIXIR) harness/repeats.exs
	cd code/app && $(ELIXIR) harness/scale.exs
	cd code/app && $(ELIXIR) harness/presence.exs
	cd code/app && $(ELIXIR) harness/multinode.exs

figures:         ## Render figur dari data/*.csv -> figures/*.pdf
	$(PY) code/analysis/plot.py

paper:           ## Build paper (XeLaTeX)
	cd paper && latexmk -xelatex -interaction=nonstopmode main.tex

reproduce: deps test experiments figures paper  ## Pipeline penuh (kecuali eksperimen Kubernetes)

clean:           ## Bersihkan build LaTeX
	cd paper && latexmk -C
