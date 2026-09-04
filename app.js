/* KKJ Inventory V1
   Frontend: Vanilla JS
   Backend: Supabase Auth + PostgreSQL
*/
const { SUPABASE_URL, SUPABASE_ANON_KEY } = window.KKJ_CONFIG || {};
const CONFIGURED =
  SUPABASE_URL &&
  SUPABASE_ANON_KEY &&
  !SUPABASE_URL.includes("PASTE_") &&
  !SUPABASE_ANON_KEY.includes("PASTE_");

const sb = CONFIGURED ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;

const state = {
  session: null,
  profile: null,
  assets: [],
  categories: [],
  locations: [],
};

const $ = (id) => document.getElementById(id);
const qa = (sel) => [...document.querySelectorAll(sel)];

function toast(message, type = "success") {
  const el = $("toast");
  el.textContent = message;
  el.className = `toast ${type} show`;
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(() => el.classList.remove("show"), 2600);
}

function clean(v) {
  return typeof v === "string" ? v.trim() : v;
}

function statusClass(status) {
  if (status === "Aktif") return "ok";
  if (status === "Rosak") return "bad";
  if (status === "Dalam Penyelenggaraan") return "warn";
  return "neutral";
}

function conditionClass(value) {
  if (value === "Baik") return "ok";
  if (value === "Rosak" || value === "Perlu Dibaiki") return "bad";
  return "warn";
}

function role() {
  return state.profile?.role || "technician";
}
function isAdmin() {
  return role() === "admin";
}

async function init() {
  $("connectionPill").textContent = CONFIGURED ? "Supabase Ready" : "Belum Configure";
  $("connectionPill").className = `status-pill ${CONFIGURED ? "ok" : "bad"}`;

  bindUI();

  if (!CONFIGURED) {
    $("authView").classList.remove("hidden");
    toast("Masukkan Supabase URL & anon key dalam config.js dahulu.", "error");
    return;
  }

  const { data: { session } } = await sb.auth.getSession();
  if (session) await enterApp(session);

  sb.auth.onAuthStateChange(async (_event, session) => {
    if (session && !state.session) await enterApp(session);
    if (!session) showLogin();
  });
}

function bindUI() {
  $("togglePassword").addEventListener("click", () => {
    const p = $("loginPassword");
    p.type = p.type === "password" ? "text" : "password";
    $("togglePassword").textContent = p.type === "password" ? "Lihat" : "Sorok";
  });

  $("loginForm").addEventListener("submit", login);
  $("logoutBtn").addEventListener("click", logout);
  $("menuBtn").addEventListener("click", () => $("sidebar").classList.toggle("open"));

  qa(".nav-item").forEach(btn => btn.addEventListener("click", () => navigate(btn.dataset.page)));
  qa("[data-go]").forEach(btn => btn.addEventListener("click", () => navigate(btn.dataset.go)));

  $("quickAddBtn").addEventListener("click", () => openAssetModal());
  $("addAssetBtn").addEventListener("click", () => openAssetModal());
  $("assetForm").addEventListener("submit", saveAsset);

  $("assetSearch").addEventListener("input", renderAssets);
  $("filterCategory").addEventListener("change", renderAssets);
  $("filterLocation").addEventListener("change", renderAssets);
  $("filterStatus").addEventListener("change", renderAssets);

  $("addCategoryBtn").addEventListener("click", () => openMasterModal("category"));
  $("addLocationBtn").addEventListener("click", () => openMasterModal("location"));
  $("masterForm").addEventListener("submit", saveMaster);

  qa("[data-close]").forEach(btn => {
    btn.addEventListener("click", () => $(btn.dataset.close).close());
  });
}

async function login(e) {
  e.preventDefault();
  if (!sb) return toast("Supabase belum dikonfigurasi.", "error");
  const email = clean($("loginEmail").value);
  const password = $("loginPassword").value;

  const submit = e.submitter;
  submit.disabled = true;
  submit.textContent = "Sedang log masuk...";
  const { data, error } = await sb.auth.signInWithPassword({ email, password });
  submit.disabled = false;
  submit.textContent = "Log Masuk";

  if (error) return toast(error.message, "error");
  await enterApp(data.session);
}

async function logout() {
  await sb.auth.signOut();
  showLogin();
}

function showLogin() {
  state.session = null;
  state.profile = null;
  $("appView").classList.add("hidden");
  $("authView").classList.remove("hidden");
}

async function enterApp(session) {
  state.session = session;
  const { data: profile, error } = await sb
    .from("profiles")
    .select("*")
    .eq("id", session.user.id)
    .single();

  if (error) {
    toast("Profil pengguna tidak ditemui. Jalankan database.sql dahulu.", "error");
    await sb.auth.signOut();
    return;
  }

  state.profile = profile;
  $("authView").classList.add("hidden");
  $("appView").classList.remove("hidden");

  $("sidebarUserName").textContent = profile.full_name || session.user.email;
  $("sidebarUserRole").textContent = profile.role;
  $("userInitial").textContent = (profile.full_name || session.user.email || "U")[0].toUpperCase();
  $("welcomeTitle").textContent = `Selamat datang, ${(profile.full_name || "Pengguna").split(" ")[0]}`;

  qa(".admin-only").forEach(el => el.classList.toggle("hidden", !isAdmin()));
  await loadAll();
}

async function loadAll() {
  await Promise.all([loadCategories(), loadLocations(), loadAssets()]);
  fillSelects();
  renderDashboard();
  renderAssets();
  renderCategories();
  renderLocations();
}

async function loadCategories() {
  const { data, error } = await sb.from("categories").select("*").order("name");
  if (error) return toast(error.message, "error");
  state.categories = data || [];
}

async function loadLocations() {
  const { data, error } = await sb.from("locations").select("*").order("name");
  if (error) return toast(error.message, "error");
  state.locations = data || [];
}

async function loadAssets() {
  const { data, error } = await sb
    .from("assets")
    .select("*, categories(name), locations(name, code)")
    .order("created_at", { ascending: false });

  if (error) return toast(error.message, "error");
  state.assets = data || [];
}

function fillSelects() {
  const catOptions = state.categories.map(x => `<option value="${x.id}">${escapeHTML(x.name)}</option>`).join("");
  const locOptions = state.locations.map(x => `<option value="${x.id}">${escapeHTML(x.name)}</option>`).join("");

  $("assetCategory").innerHTML = `<option value="">Pilih kategori</option>${catOptions}`;
  $("filterCategory").innerHTML = `<option value="">Semua kategori</option>${catOptions}`;
  $("assetLocation").innerHTML = `<option value="">Pilih lokasi</option>${locOptions}`;
  $("filterLocation").innerHTML = `<option value="">Semua lokasi</option>${locOptions}`;
}

function renderDashboard() {
  const total = state.assets.length;
  const active = state.assets.filter(a => a.status === "Aktif" && a.condition === "Baik").length;
  const attention = state.assets.filter(a => a.status === "Rosak" || a.status === "Dalam Penyelenggaraan" || ["Perlu Dibaiki","Rosak"].includes(a.condition)).length;

  $("statTotal").textContent = total;
  $("statActive").textContent = active;
  $("statAttention").textContent = attention;
  $("statLocations").textContent = state.locations.length;

  const recent = state.assets.slice(0, 5);
  $("recentAssets").innerHTML = recent.length ? recent.map(a => `
    <div class="recent-item">
      <div><strong>${escapeHTML(a.asset_name)}</strong><small>${escapeHTML(a.asset_tag)} • ${escapeHTML(a.locations?.name || "-")}</small></div>
      <span class="badge ${statusClass(a.status)}">${escapeHTML(a.status)}</span>
    </div>`).join("") : `<div class="empty-state">Belum ada aset.</div>`;

  const statuses = [
    ["Aktif", state.assets.filter(a => a.status === "Aktif").length],
    ["Penyelenggaraan", state.assets.filter(a => a.status === "Dalam Penyelenggaraan").length],
    ["Rosak", state.assets.filter(a => a.status === "Rosak").length],
    ["Dilupuskan", state.assets.filter(a => a.status === "Dilupuskan").length],
  ];
  $("healthBars").innerHTML = statuses.map(([name, count]) => {
    const pct = total ? Math.round((count / total) * 100) : 0;
    return `<div class="health-row">
      <div class="health-label"><span>${name}</span><strong>${count} (${pct}%)</strong></div>
      <div class="bar"><i style="width:${pct}%"></i></div>
    </div>`;
  }).join("");
}

function getFilteredAssets() {
  const q = clean($("assetSearch").value).toLowerCase();
  const cat = $("filterCategory").value;
  const loc = $("filterLocation").value;
  const status = $("filterStatus").value;

  return state.assets.filter(a => {
    const hay = `${a.asset_tag} ${a.asset_name} ${a.serial_number || ""} ${a.brand || ""} ${a.model || ""}`.toLowerCase();
    return (!q || hay.includes(q)) &&
      (!cat || a.category_id === cat) &&
      (!loc || a.location_id === loc) &&
      (!status || a.status === status);
  });
}

function renderAssets() {
  const rows = getFilteredAssets();
  $("assetEmpty").classList.toggle("hidden", rows.length > 0);
  $("assetTableBody").innerHTML = rows.map(a => `
    <tr>
      <td><strong>${escapeHTML(a.asset_tag)}</strong></td>
      <td class="asset-name"><strong>${escapeHTML(a.asset_name)}</strong><small>${escapeHTML([a.brand,a.model].filter(Boolean).join(" ") || a.serial_number || "-")}</small></td>
      <td>${escapeHTML(a.categories?.name || "-")}</td>
      <td>${escapeHTML(a.locations?.name || "-")}</td>
      <td><span class="badge ${statusClass(a.status)}">${escapeHTML(a.status)}</span></td>
      <td><span class="badge ${conditionClass(a.condition)}">${escapeHTML(a.condition)}</span></td>
      <td><div class="actions">
        <button class="mini-btn" onclick="window.editAsset('${a.id}')">Edit</button>
        ${isAdmin() ? `<button class="mini-btn danger" onclick="window.deleteAsset('${a.id}')">Padam</button>` : ""}
      </div></td>
    </tr>`).join("");
}

function renderCategories() {
  $("categoryTableBody").innerHTML = state.categories.map(c => `
    <tr>
      <td><strong>${escapeHTML(c.name)}</strong></td>
      <td>${escapeHTML(c.description || "-")}</td>
      <td><div class="actions">
        ${isAdmin() ? `<button class="mini-btn" onclick="window.editMaster('category','${c.id}')">Edit</button>
        <button class="mini-btn danger" onclick="window.deleteMaster('category','${c.id}')">Padam</button>` : `<span class="badge neutral">View only</span>`}
      </div></td>
    </tr>`).join("");
}

function renderLocations() {
  $("locationTableBody").innerHTML = state.locations.map(l => `
    <tr>
      <td><strong>${escapeHTML(l.name)}</strong></td>
      <td>${escapeHTML(l.code || "-")}</td>
      <td>${escapeHTML(l.description || "-")}</td>
      <td><div class="actions">
        ${isAdmin() ? `<button class="mini-btn" onclick="window.editMaster('location','${l.id}')">Edit</button>
        <button class="mini-btn danger" onclick="window.deleteMaster('location','${l.id}')">Padam</button>` : `<span class="badge neutral">View only</span>`}
      </div></td>
    </tr>`).join("");
}

function navigate(page) {
  qa(".page").forEach(p => p.classList.remove("active"));
  qa(".nav-item").forEach(b => b.classList.toggle("active", b.dataset.page === page));
  $(`page-${page}`).classList.add("active");
  $("pageTitle").textContent = ({dashboard:"Dashboard",assets:"Pengurusan Aset",categories:"Kategori",locations:"Lokasi"})[page] || page;
  $("sidebar").classList.remove("open");
}

function openAssetModal(asset = null) {
  $("assetForm").reset();
  $("assetId").value = "";
  $("assetModalTitle").textContent = asset ? "Edit Aset" : "Tambah Aset";
  if (asset) {
    $("assetId").value = asset.id;
    $("assetTag").value = asset.asset_tag || "";
    $("assetName").value = asset.asset_name || "";
    $("assetCategory").value = asset.category_id || "";
    $("assetLocation").value = asset.location_id || "";
    $("assetSerial").value = asset.serial_number || "";
    $("assetBrand").value = asset.brand || "";
    $("assetModel").value = asset.model || "";
    $("assetStatus").value = asset.status || "Aktif";
    $("assetCondition").value = asset.condition || "Baik";
    $("purchaseDate").value = asset.purchase_date || "";
    $("purchasePrice").value = asset.purchase_price ?? "";
    $("warrantyUntil").value = asset.warranty_until || "";
    $("assetNotes").value = asset.notes || "";
  }
  $("assetModal").showModal();
}

window.editAsset = (id) => openAssetModal(state.assets.find(a => a.id === id));

window.deleteAsset = async (id) => {
  if (!isAdmin()) return toast("Hanya Admin boleh memadam aset.", "error");
  if (!confirm("Padam aset ini? Tindakan ini tidak boleh dibatalkan.")) return;
  const { error } = await sb.from("assets").delete().eq("id", id);
  if (error) return toast(error.message, "error");
  toast("Aset berjaya dipadam.");
  await loadAssets();
  renderAssets();
  renderDashboard();
};

async function saveAsset(e) {
  e.preventDefault();
  const id = $("assetId").value;
  const payload = {
    asset_tag: clean($("assetTag").value).toUpperCase(),
    asset_name: clean($("assetName").value),
    category_id: $("assetCategory").value,
    location_id: $("assetLocation").value,
    serial_number: clean($("assetSerial").value) || null,
    brand: clean($("assetBrand").value) || null,
    model: clean($("assetModel").value) || null,
    status: $("assetStatus").value,
    condition: $("assetCondition").value,
    purchase_date: $("purchaseDate").value || null,
    purchase_price: $("purchasePrice").value ? Number($("purchasePrice").value) : null,
    warranty_until: $("warrantyUntil").value || null,
    notes: clean($("assetNotes").value) || null,
    updated_by: state.session.user.id
  };

  let result;
  if (id) {
    result = await sb.from("assets").update(payload).eq("id", id);
  } else {
    payload.created_by = state.session.user.id;
    result = await sb.from("assets").insert(payload);
  }

  if (result.error) return toast(result.error.message, "error");
  $("assetModal").close();
  toast(id ? "Aset berjaya dikemaskini." : "Aset berjaya ditambah.");
  await loadAssets();
  renderAssets();
  renderDashboard();
}

function openMasterModal(type, item = null) {
  if (!isAdmin()) return toast("Hanya Admin boleh mengurus master data.", "error");
  $("masterForm").reset();
  $("masterType").value = type;
  $("masterId").value = item?.id || "";
  $("masterModalTitle").textContent = `${item ? "Edit" : "Tambah"} ${type === "category" ? "Kategori" : "Lokasi"}`;
  $("masterName").value = item?.name || "";
  $("masterCode").value = item?.code || "";
  $("masterDescription").value = item?.description || "";
  $("masterCodeWrap").classList.toggle("hidden", type === "category");
  $("masterModal").showModal();
}

window.editMaster = (type, id) => {
  const list = type === "category" ? state.categories : state.locations;
  openMasterModal(type, list.find(x => x.id === id));
};

window.deleteMaster = async (type, id) => {
  if (!isAdmin()) return;
  const table = type === "category" ? "categories" : "locations";
  if (!confirm(`Padam ${type === "category" ? "kategori" : "lokasi"} ini?`)) return;
  const { error } = await sb.from(table).delete().eq("id", id);
  if (error) return toast("Tidak boleh dipadam jika masih digunakan oleh aset.", "error");
  toast("Data berjaya dipadam.");
  await loadAll();
};

async function saveMaster(e) {
  e.preventDefault();
  const type = $("masterType").value;
  const id = $("masterId").value;
  const table = type === "category" ? "categories" : "locations";
  const payload = {
    name: clean($("masterName").value),
    description: clean($("masterDescription").value) || null
  };
  if (type === "location") payload.code = clean($("masterCode").value).toUpperCase() || null;

  const result = id
    ? await sb.from(table).update(payload).eq("id", id)
    : await sb.from(table).insert(payload);

  if (result.error) return toast(result.error.message, "error");
  $("masterModal").close();
  toast("Data berjaya disimpan.");
  await loadAll();
}

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&","&amp;")
    .replaceAll("<","&lt;")
    .replaceAll(">","&gt;")
    .replaceAll('"',"&quot;")
    .replaceAll("'","&#039;");
}

init();
