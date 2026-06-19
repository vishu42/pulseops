const state = {
  companies: [],
  selectedCompanyId: null,
  urls: [],
  selectedURLId: null,
  probeSummary: null
};

const elements = {
  healthBadge: document.querySelector("#healthBadge"),
  refreshButton: document.querySelector("#refreshButton"),
  companyForm: document.querySelector("#companyForm"),
  companyName: document.querySelector("#companyName"),
  companySlug: document.querySelector("#companySlug"),
  companiesList: document.querySelector("#companiesList"),
  selectedCompanyEyebrow: document.querySelector("#selectedCompanyEyebrow"),
  selectedCompanySlug: document.querySelector("#selectedCompanySlug"),
  urlSearch: document.querySelector("#urlSearch"),
  urlCount: document.querySelector("#urlCount"),
  urlsTable: document.querySelector("#urlsTable"),
  historyWindow: document.querySelector("#historyWindow"),
  probeTitle: document.querySelector("#probeTitle"),
  latestOutcome: document.querySelector("#latestOutcome"),
  latestStatusCode: document.querySelector("#latestStatusCode"),
  latestLatency: document.querySelector("#latestLatency"),
  latestCheckedAt: document.querySelector("#latestCheckedAt"),
  probeBuckets: document.querySelector("#probeBuckets"),
  urlForm: document.querySelector("#urlForm"),
  urlValue: document.querySelector("#urlValue"),
  urlMethod: document.querySelector("#urlMethod"),
  urlInterval: document.querySelector("#urlInterval"),
  urlTimeout: document.querySelector("#urlTimeout"),
  urlExpected: document.querySelector("#urlExpected"),
  message: document.querySelector("#message")
};

function selectedCompany() {
  return state.companies.find((company) => company.id === state.selectedCompanyId) || null;
}

function selectedURL() {
  return state.urls.find((monitoredURL) => monitoredURL.id === state.selectedURLId) || null;
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {})
    },
    ...options
  });

  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;

  if (!response.ok) {
    throw new Error(payload?.error || `Request failed: ${response.status}`);
  }

  return payload;
}

async function checkHealth() {
  try {
    await api("/healthz");
    elements.healthBadge.textContent = "API online";
    elements.healthBadge.className = "health ok";
  } catch (error) {
    elements.healthBadge.textContent = "API offline";
    elements.healthBadge.className = "health error";
  }
}

async function loadCompanies() {
  try {
    const payload = await api("/api/v1/companies");
    state.companies = payload.companies || [];
    if (!state.selectedCompanyId && state.companies.length > 0) {
      state.selectedCompanyId = state.companies[0].id;
    }
    if (state.selectedCompanyId && !selectedCompany()) {
      state.selectedCompanyId = state.companies[0]?.id || null;
    }
    renderCompanies();
    await loadURLs();
  } catch (error) {
    renderCompanies(error.message);
    renderURLs(error.message);
  }
}

async function loadURLs() {
  const company = selectedCompany();
  if (!company) {
    state.urls = [];
    state.selectedURLId = null;
    state.probeSummary = null;
    renderSelectedCompany();
    renderURLs();
    renderProbeSummary();
    setURLFormEnabled(false);
    return;
  }

  setURLFormEnabled(true);
  renderSelectedCompany();

  const query = elements.urlSearch.value.trim();
  const suffix = query ? `?q=${encodeURIComponent(query)}` : "";
  try {
    const payload = await api(`/api/v1/companies/${company.id}/urls${suffix}`);
    state.urls = payload.urls || [];
    if (state.selectedURLId && !selectedURL()) {
      state.selectedURLId = null;
      state.probeSummary = null;
    }
    renderURLs();
    await loadProbeSummary();
  } catch (error) {
    renderURLs(error.message);
    renderProbeSummary(error.message);
  }
}

async function loadProbeSummary() {
  const monitoredURL = selectedURL();
  if (!monitoredURL) {
    state.probeSummary = null;
    renderProbeSummary();
    return;
  }

  try {
    const hours = Number(elements.historyWindow.value || 24);
    state.probeSummary = await api(
      `/api/v1/urls/${monitoredURL.id}/probe-summary?hours=${hours}&bucket_minutes=5`
    );
    renderURLs();
    renderProbeSummary();
  } catch (error) {
    renderProbeSummary(error.message);
  }
}

function renderCompanies(error) {
  elements.companiesList.replaceChildren();

  if (error) {
    elements.companiesList.append(empty(`Could not load companies: ${error}`));
    return;
  }

  if (state.companies.length === 0) {
    elements.companiesList.append(empty("No companies yet"));
    return;
  }

  for (const company of state.companies) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `company-row${company.id === state.selectedCompanyId ? " active" : ""}`;
    button.innerHTML = `<strong></strong><span></span>`;
    button.querySelector("strong").textContent = company.name;
    button.querySelector("span").textContent = company.slug;
    button.addEventListener("click", async () => {
      state.selectedCompanyId = company.id;
      state.selectedURLId = null;
      state.probeSummary = null;
      renderCompanies();
      await loadURLs();
    });
    elements.companiesList.append(button);
  }
}

function renderSelectedCompany() {
  const company = selectedCompany();
  elements.selectedCompanyEyebrow.textContent = company ? company.name : "No company selected";
  elements.selectedCompanySlug.textContent = company ? company.slug : "";
}

function renderURLs(error) {
  elements.urlsTable.replaceChildren();
  elements.urlCount.textContent = `${state.urls.length} ${state.urls.length === 1 ? "URL" : "URLs"}`;

  if (error) {
    const row = singleTableRow(`Could not load URLs: ${error}`);
    elements.urlsTable.append(row);
    return;
  }

  if (!selectedCompany()) {
    elements.urlsTable.append(singleTableRow("Select a company"));
    return;
  }

  if (state.urls.length === 0) {
    elements.urlsTable.append(singleTableRow("No URLs registered"));
    return;
  }

  for (const monitoredURL of state.urls) {
    const row = document.createElement("tr");
    row.className = monitoredURL.id === state.selectedURLId ? "selected-row" : "";
    row.innerHTML = `
      <td class="url-cell"></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
    `;
    row.children[0].textContent = monitoredURL.url;
    row.children[1].textContent = monitoredURL.method;
    row.children[2].textContent = `${monitoredURL.check_interval_seconds}s`;
    row.children[3].textContent = `${monitoredURL.timeout_ms}ms`;
    row.children[4].textContent = monitoredURL.id === state.selectedURLId && state.probeSummary?.latest_status
      ? state.probeSummary.latest_status.outcome
      : "-";
    row.addEventListener("click", async () => {
      state.selectedURLId = monitoredURL.id;
      state.probeSummary = null;
      renderURLs();
      renderProbeSummary();
      await loadProbeSummary();
    });
    elements.urlsTable.append(row);
  }
}

function renderProbeSummary(error) {
  const monitoredURL = selectedURL();
  elements.probeBuckets.replaceChildren();

  if (error) {
    elements.probeTitle.textContent = "Could not load probe summary";
    resetLatestMetrics();
    elements.probeBuckets.append(singleTableRow(error, 5));
    return;
  }

  if (!monitoredURL) {
    elements.probeTitle.textContent = "Select a monitor";
    resetLatestMetrics();
    elements.probeBuckets.append(singleTableRow("Click a URL row to inspect probe averages", 5));
    return;
  }

  elements.probeTitle.textContent = monitoredURL.url;
  const latest = state.probeSummary?.latest_status;
  if (latest) {
    elements.latestOutcome.textContent = latest.outcome;
    elements.latestStatusCode.textContent = latest.status_code ?? "-";
    elements.latestLatency.textContent = latest.latency_ms == null ? "-" : `${latest.latency_ms}ms`;
    elements.latestCheckedAt.textContent = formatDateTime(latest.checked_at);
  } else {
    resetLatestMetrics();
  }

  const buckets = state.probeSummary?.buckets || [];
  if (buckets.length === 0) {
    elements.probeBuckets.append(singleTableRow("No probe results in this window yet", 5));
    return;
  }

  for (const bucket of buckets) {
    const row = document.createElement("tr");
    row.innerHTML = `
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
    `;
    row.children[0].textContent = formatDateTime(bucket.bucket_start);
    row.children[1].textContent =
      bucket.avg_latency_ms == null ? "-" : `${Math.round(bucket.avg_latency_ms)}ms`;
    row.children[2].textContent = `${bucket.uptime_percent.toFixed(2)}%`;
    row.children[3].textContent =
      `${bucket.total_checks} (${bucket.up_checks} up, ${bucket.down_checks} down, ${bucket.error_checks} err)`;
    row.children[4].textContent = bucket.last_outcome || "-";
    elements.probeBuckets.append(row);
  }
}

function empty(text) {
  const div = document.createElement("div");
  div.className = "empty";
  div.textContent = text;
  return div;
}

function singleTableRow(text, colSpan = 5) {
  const row = document.createElement("tr");
  const cell = document.createElement("td");
  cell.colSpan = colSpan;
  cell.className = "empty";
  cell.textContent = text;
  row.append(cell);
  return row;
}

function resetLatestMetrics() {
  elements.latestOutcome.textContent = "-";
  elements.latestStatusCode.textContent = "-";
  elements.latestLatency.textContent = "-";
  elements.latestCheckedAt.textContent = "-";
}

function formatDateTime(value) {
  if (!value) return "-";
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function setURLFormEnabled(enabled) {
  for (const field of elements.urlForm.elements) {
    field.disabled = !enabled;
  }
}

function setMessage(text, type = "") {
  elements.message.textContent = text;
  elements.message.className = `message ${type}`.trim();
}

function parseExpectedRange(value) {
  const match = value.trim().match(/^(\d{3})(?:\s*-\s*(\d{3}))?$/);
  if (!match) {
    throw new Error("Expected status must look like 200-399");
  }
  const min = Number(match[1]);
  const max = Number(match[2] || match[1]);
  if (min > max) {
    throw new Error("Expected status minimum cannot exceed maximum");
  }
  return [min, max];
}

elements.companyName.addEventListener("input", () => {
  if (elements.companySlug.dataset.dirty === "true") return;
  elements.companySlug.value = elements.companyName.value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
});

elements.companySlug.addEventListener("input", () => {
  elements.companySlug.dataset.dirty = "true";
});

elements.companyForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setMessage("");
  try {
    const company = await api("/api/v1/companies", {
      method: "POST",
      body: JSON.stringify({
        name: elements.companyName.value.trim(),
        slug: elements.companySlug.value.trim()
      })
    });
    state.selectedCompanyId = company.id;
    elements.companyForm.reset();
    elements.companySlug.dataset.dirty = "false";
    setMessage("Company created", "ok");
    await loadCompanies();
  } catch (error) {
    setMessage(error.message, "error");
  }
});

elements.urlForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const company = selectedCompany();
  if (!company) return;

  setMessage("");
  try {
    const [expectedMin, expectedMax] = parseExpectedRange(elements.urlExpected.value);
    await api(`/api/v1/companies/${company.id}/urls`, {
      method: "POST",
      body: JSON.stringify({
        url: elements.urlValue.value.trim(),
        method: elements.urlMethod.value,
        timeout_ms: Number(elements.urlTimeout.value),
        check_interval_seconds: Number(elements.urlInterval.value),
        expected_status_min: expectedMin,
        expected_status_max: expectedMax
      })
    });
    elements.urlForm.reset();
    elements.urlMethod.value = "GET";
    elements.urlInterval.value = "60";
    elements.urlTimeout.value = "5000";
    elements.urlExpected.value = "200-399";
    setMessage("Monitor added", "ok");
    await loadURLs();
  } catch (error) {
    setMessage(error.message, "error");
  }
});

elements.refreshButton.addEventListener("click", async () => {
  await checkHealth();
  await loadCompanies();
});

elements.historyWindow.addEventListener("change", loadProbeSummary);

let searchTimer = null;
elements.urlSearch.addEventListener("input", () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(loadURLs, 250);
});

setURLFormEnabled(false);
renderProbeSummary();
checkHealth();
loadCompanies();
