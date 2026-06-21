defmodule GraceConvergence.Workers do
  @moduledoc """
  Helper untuk **membuat, menghitung, dan menemukan** worker stateful
  (`GraceConvergence.StatefulWorker`).

  Ada satu keputusan desain halus tapi penting di sini. Kita memisahkan dua tanggung jawab:

    * *Identitas* (nama unik se-cluster) berasal dari `Horde.Registry`, sehingga node mana pun bisa
      menemukan worker lewat key.
    * *Hosting* (node mana yang sebenarnya menjalankan proses) dilakukan oleh `DynamicSupervisor`
      **lokal** di tiap node — BUKAN oleh supervisor terdistribusi milik Horde.

  Kenapa tidak biarkan Horde meng-host juga? Horde akan menempatkan proses yang di-restart di mana
  pun hash-ring internalnya menunjuk, yang bisa jadi justru node yang sedang ditinggalkan — persis
  node yang ingin kita kosongkan. Dengan meng-host secara lokal dan memilih sendiri node tujuan saat
  handoff, controller-lah yang memutuskan *di mana* state worker mendarat. (`DynamicSupervisor` adalah
  supervisor untuk anak yang dimulai sesuai kebutuhan saat runtime, bukan daftar tetap saat boot.)

  Beberapa fungsi memakai `:rpc.call/4`, *remote procedure call* milik Erlang: menjalankan sebuah
  fungsi di node lain dan mengembalikan hasilnya — beginilah cara kita memulai worker "di sana".
  """
  alias GraceConvergence.StatefulWorker

  @registry GraceConvergence.Registry
  @sup GraceConvergence.WorkerSup

  @doc "Memulai satu worker di supervisor lokal node INI, opsional dengan `state` awal."
  def start_local(id, state \\ nil) do
    DynamicSupervisor.start_child(@sup, {StatefulWorker, id: id, state: state})
  end

  @doc "Memulai satu worker di `node` tertentu dengan menjalankan `start_local/2` di sana via RPC."
  def start_on(node, id, state \\ nil) do
    :rpc.call(node, __MODULE__, :start_local, [id, state])
  end

  @doc """
  Memulai `n` worker baru dengan key `"<prefix><i>"`, disebar round-robin ke setiap node di cluster
  (node ini plus para peer). `rem(i, length(nodes))` memutar daftar node secara bergiliran.
  """
  def start_many(n, prefix \\ "w") when is_integer(n) and n > 0 do
    nodes = [Node.self() | Node.list()]
    Enum.map(1..n, fn i -> start_on(Enum.at(nodes, rem(i, length(nodes))), "#{prefix}#{i}") end)
  end

  @doc """
  Memulai `n` worker baru semuanya di node INI. Dalam eksperimen drain inilah node yang "pergi": kita
  menumpuk backlog di sini lalu mengukur seberapa baik ia meng-handoff semuanya sebelum dimatikan.
  """
  def start_many_local(n, prefix \\ "w") when is_integer(n) and n > 0 do
    Enum.map(1..n, fn i -> start_local("#{prefix}#{i}") end)
  end

  @doc "Menghentikan setiap worker yang di-host node ini (untuk membersihkan antar-skenario)."
  def stop_all do
    # `which_children/1` mendaftar anak supervisor sebagai tuple {id, pid, type, modules};
    # kita hentikan tiap anak yang pid-nya proses sungguhan.
    for {_, pid, _, _} <- DynamicSupervisor.which_children(@sup), is_pid(pid) do
      DynamicSupervisor.terminate_child(@sup, pid)
    end

    :ok
  end

  @doc """
  Semua pasangan `{key, pid}` yang terdaftar di seluruh cluster. Argumen ke `Horde.Registry.select/2`
  adalah *match specification* (kueri pola-cocok ala Erlang): `{:"$1", :"$2", :"$3"}` mengikat
  key/pid/value, dan `[{{:"$1", :"$2"}}]` berarti "kembalikan pasangan {key, pid}".
  """
  def all do
    Horde.Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Pasangan `{key, pid}` yang prosesnya di-host di node INI **dan masih hidup**.

  Cek `Process.alive?/1` itu penting karena waktu CRDT: saat sebuah worker mati, entri registry-nya
  masih tertinggal sesaat sampai de-registrasinya menyebar ke semua node. Tanpa cek hidup-mati, loop
  drain bisa terus "menemukan" entri mati itu dan berputar selamanya.
  """
  def local do
    Enum.filter(all(), fn {_key, pid} -> node(pid) == Node.self() and Process.alive?(pid) end)
  end

  @doc "Berapa worker hidup yang di-host di node ini."
  def local_count, do: length(local())

  @doc "Berapa worker yang ada di seluruh cluster."
  def count, do: length(all())

  @doc """
  Memilih node yang bertahan sebagai tujuan handoff: peer mana pun yang terhubung, dipilih acak.
  Mengembalikan `nil` saat node ini terisolasi (tak ada peer), sehingga tak ada tempat handoff.
  """
  def survivor do
    case Node.list() do
      [] -> nil
      nodes -> Enum.random(nodes)
    end
  end
end
