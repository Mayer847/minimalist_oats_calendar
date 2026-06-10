window.oatsGoogleDrive = {
  clientId: null,
  tokenClient: null,
  accessToken: null,
  backupFileId: null,
  backupFileName: 'oats_schedule_backup.json',
  status: 'Disconnected',
};

const OATS_DRIVE_SCOPE = 'https://www.googleapis.com/auth/drive.appdata';

function waitForGlobal(path, timeoutMs = 15000) {
  const parts = path.split('.');
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      let current = window;
      for (const part of parts) current = current && current[part];
      if (current) { clearInterval(timer); resolve(current); }
      else if (Date.now() - started > timeoutMs) { clearInterval(timer); reject(new Error(`Timed out waiting for ${path}`)); }
    }, 50);
  });
}

window.oatsGoogleDriveInit = async function(clientId) {
  if (!clientId || clientId.includes('PASTE_YOUR_GOOGLE_CLIENT_ID_HERE')) throw new Error('Missing GOOGLE_CLIENT_ID');
  window.oatsGoogleDrive.clientId = clientId;
  window.oatsGoogleDrive.status = 'Loading Google APIs...';
  await waitForGlobal('google.accounts.oauth2');
  await waitForGlobal('gapi');
  await new Promise((resolve) => gapi.load('client', resolve));
  await gapi.client.init({});
  await gapi.client.load('drive', 'v3');
  window.oatsGoogleDrive.tokenClient = google.accounts.oauth2.initTokenClient({ client_id: clientId, scope: OATS_DRIVE_SCOPE, callback: () => {} });
  window.oatsGoogleDrive.status = 'Ready';
  return true;
};

window.oatsGoogleDriveConnect = async function() {
  const state = window.oatsGoogleDrive;
  if (!state.tokenClient) throw new Error('Google Drive sync is not initialized');
  state.status = 'Waiting for Google consent...';
  const tokenResponse = await new Promise((resolve, reject) => {
    state.tokenClient.callback = (response) => response.error ? reject(response) : resolve(response);
    state.tokenClient.requestAccessToken({ prompt: state.accessToken ? '' : 'consent' });
  });
  state.accessToken = tokenResponse.access_token;
  gapi.client.setToken({ access_token: state.accessToken });
  state.status = 'Connected';
  return state.status;
};

window.oatsGoogleDriveSignOut = async function() {
  const state = window.oatsGoogleDrive;
  if (state.accessToken && google?.accounts?.oauth2?.revoke) google.accounts.oauth2.revoke(state.accessToken, () => {});
  state.accessToken = null;
  state.backupFileId = null;
  gapi.client.setToken(null);
  state.status = 'Disconnected';
  return true;
};

async function findBackupFile() {
  const state = window.oatsGoogleDrive;
  if (state.backupFileId) return state.backupFileId;
  const response = await gapi.client.drive.files.list({ spaces: 'appDataFolder', q: `name='${state.backupFileName}' and trashed=false`, fields: 'files(id,name,modifiedTime)', pageSize: 1 });
  const files = response.result.files || [];
  if (files.length > 0) { state.backupFileId = files[0].id; return state.backupFileId; }
  return null;
}

window.oatsGoogleDriveLoadBackup = async function() {
  const state = window.oatsGoogleDrive;
  if (!state.accessToken) throw new Error('Not connected to Google Drive');
  state.status = 'Loading backup...';
  const fileId = await findBackupFile();
  if (!fileId) { state.status = 'Connected - no cloud backup yet'; return null; }
  const response = await gapi.client.drive.files.get({ fileId, alt: 'media' });
  state.status = 'Cloud backup loaded';
  if (typeof response.body === 'string') return JSON.parse(response.body);
  return response.result;
};

window.oatsGoogleDriveSaveBackup = async function(jsonText) {
  const state = window.oatsGoogleDrive;
  if (!state.accessToken) throw new Error('Not connected to Google Drive');
  state.status = 'Syncing...';
  const fileId = await findBackupFile();
  const metadata = { name: state.backupFileName, parents: ['appDataFolder'] };
  const boundary = '-------oats_boundary_' + Date.now();
  const delimiter = `\r\n--${boundary}\r\n`;
  const closeDelimiter = `\r\n--${boundary}--`;
  const body = delimiter + 'Content-Type: application/json; charset=UTF-8\r\n\r\n' + JSON.stringify(metadata) + delimiter + 'Content-Type: application/json; charset=UTF-8\r\n\r\n' + jsonText + closeDelimiter;
  const path = fileId ? `/upload/drive/v3/files/${fileId}?uploadType=multipart&fields=id,modifiedTime` : '/upload/drive/v3/files?uploadType=multipart&fields=id,modifiedTime';
  const method = fileId ? 'PATCH' : 'POST';
  const response = await gapi.client.request({ path, method, headers: { 'Content-Type': `multipart/related; boundary=${boundary}` }, body });
  state.backupFileId = response.result.id;
  state.status = 'Synced';
  return response.result;
};

window.oatsGoogleDriveGetStatus = async function() { return window.oatsGoogleDrive.status; };
