import { GoogleGenAI } from '@google/genai';

// =============================================================
// GEMINI AI CONFIG
// Uses the @google/genai SDK (stable v1 API)
// =============================================================
const genAI = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY || '' });

// =============================================================
// INTERFACES
// =============================================================
export interface TriageResult {
  incidentType: string;         // Fire, Flood, Earthquake, Accident, Medical, Violence, Gas Leak, Unknown
  severity: 'LOW' | 'MODERATE' | 'HIGH' | 'CRITICAL';
  confidence: number;           // 0-100
  summary: string;              // 1-2 sentence professional summary for responders
  recommendedActions: string[]; // Immediate actions for emergency responders
}

export interface SitrepResult {
  classification:       string;   // e.g. "CRITICAL — Building Fire"
  situation:            string;   // Current state paragraph
  missionObjective:     string;   // What responders must achieve
  immediateActions:     string[]; // Priority ordered action list
  resourcesNeeded:      string[]; // Personnel, equipment
  safetyConsiderations: string[]; // Hazards, exclusion zones
  estimatedImpact:      string;   // Potential affected people / area
  generatedAt:          string;   // ISO timestamp
}

// =============================================================
// TRIAGE INCIDENT
// Sends user report to Gemini AI for classification and returns
// structured JSON triage data. Never throws — returns a safe
// fallback on AI failure so incidents are never blocked.
// =============================================================
export async function triageIncident(
  message: string,
  lat: number,
  lng: number
): Promise<TriageResult> {

  const prompt = `You are an emergency dispatch AI for a crisis response system.
Analyze this incident report and respond with ONLY valid JSON (no markdown, no explanation).

Incident Report: "${message}"
Location: Lat ${lat}, Lng ${lng}

Classify and respond with this exact JSON structure:
{
  "incidentType": "<one of: Fire, Flood, Earthquake, Accident, Medical, Violence, Gas Leak, Structural Collapse, Missing Person, Unknown>",
  "severity": "<one of: LOW, MODERATE, HIGH, CRITICAL>",
  "confidence": <integer 0-100>,
  "summary": "<1-2 professional sentences for emergency responders>",
  "recommendedActions": ["<action 1>", "<action 2>", "<action 3>"]
}

Severity guide:
- LOW: Minor, no immediate danger
- MODERATE: Attention needed, some risk
- HIGH: Urgent response required, significant danger
- CRITICAL: Immediate life-threatening emergency

Always respond ONLY with the JSON object, no other text.`;

  try {
    const result = await genAI.models.generateContent({
      model: 'gemini-2.0-flash',
      contents: prompt,
      config: { responseMimeType: 'application/json' },
    });

    const text  = result.text || '{}';
    const clean = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    const triage = JSON.parse(clean) as TriageResult;

    const validTypes      = ['Fire', 'Flood', 'Earthquake', 'Accident', 'Medical', 'Violence', 'Gas Leak', 'Structural Collapse', 'Missing Person', 'Unknown'];
    const validSeverities = ['LOW', 'MODERATE', 'HIGH', 'CRITICAL'];

    return {
      incidentType:       validTypes.includes(triage.incidentType) ? triage.incidentType : 'Unknown',
      severity:           validSeverities.includes(triage.severity) ? triage.severity as TriageResult['severity'] : 'MODERATE',
      confidence:         Math.min(100, Math.max(0, triage.confidence || 50)),
      summary:            triage.summary || 'Incident reported — details pending.',
      recommendedActions: Array.isArray(triage.recommendedActions) ? triage.recommendedActions : [],
    };
  } catch (err) {
    console.error('🔴 [AI] Triage failed:', (err as Error).message);
    return {
      incidentType: 'Unknown',
      severity: 'HIGH',
      confidence: 50,
      summary: 'Automated triage unavailable. Manual review required.',
      recommendedActions: ['Dispatch responders', 'Assess on-site'],
    };
  }
}

// =============================================================
// GENERATE SITREP (Situation Report)
// Produces a military-grade SITREP from all incident data.
// Called by GET /incidents/:id/sitrep — for emergency commanders.
// =============================================================
export async function generateSitrep(incident: {
  incidentType:       string;
  severity:           string;
  aiSummary:          string;
  message:            string;
  lat:                number;
  lng:                number;
  address?:           string;
  corroborationCount: number;
  status:             string;
  createdAt:          string;
  updates: Array<{ message: string; updateType: string; createdAt: string; authorName?: string }>;
}): Promise<SitrepResult> {

  const updatesText = incident.updates.length > 0
    ? incident.updates.map(u => `[${u.updateType}] ${u.message} (${u.authorName || 'System'})`).join('\n')
    : 'No updates yet.';

  const prompt = `You are a military-grade emergency operations AI.
Generate a concise SITREP (Situation Report) for an emergency incident commander.
Respond ONLY with valid JSON, no markdown.

INCIDENT DATA:
- Type: ${incident.incidentType}
- Severity: ${incident.severity}
- Status: ${incident.status}
- AI Summary: ${incident.aiSummary}
- Original Report: "${incident.message}"
- Location: Lat ${incident.lat}, Lng ${incident.lng}${incident.address ? `, Address: ${incident.address}` : ''}
- Corroborated by: ${incident.corroborationCount} independent report(s)
- Reported at: ${incident.createdAt}

TIMELINE OF UPDATES:
${updatesText}

Generate this exact JSON:
{
  "classification": "<severity level> — <incident type> at <brief location>",
  "situation": "<2-3 sentences: current state, what is happening right now>",
  "missionObjective": "<single clear sentence: what responders must achieve>",
  "immediateActions": ["<priority action 1>", "<priority action 2>", "<priority action 3>", "<priority action 4>"],
  "resourcesNeeded": ["<resource 1>", "<resource 2>", "<resource 3>"],
  "safetyConsiderations": ["<hazard 1>", "<hazard 2>"],
  "estimatedImpact": "<brief estimate of affected population/area>"
}

Be concise, direct, and actionable. Use emergency services terminology.`;

  try {
    const result = await genAI.models.generateContent({
      model: 'gemini-2.0-flash',
      contents: prompt,
      config: { responseMimeType: 'application/json' },
    });

    const text   = result.text || '{}';
    const clean  = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    const sitrep = JSON.parse(clean) as SitrepResult;

    return {
      classification:       sitrep.classification       || `${incident.severity} — ${incident.incidentType}`,
      situation:            sitrep.situation            || incident.aiSummary,
      missionObjective:     sitrep.missionObjective     || 'Respond and secure the incident.',
      immediateActions:     Array.isArray(sitrep.immediateActions)     ? sitrep.immediateActions     : [],
      resourcesNeeded:      Array.isArray(sitrep.resourcesNeeded)      ? sitrep.resourcesNeeded      : [],
      safetyConsiderations: Array.isArray(sitrep.safetyConsiderations) ? sitrep.safetyConsiderations : [],
      estimatedImpact:      sitrep.estimatedImpact      || 'Unknown',
      generatedAt:          new Date().toISOString(),
    };
  } catch (err) {
    console.error('🔴 [AI] SITREP generation failed:', (err as Error).message);
    return {
      classification:       `${incident.severity} — ${incident.incidentType}`,
      situation:            incident.aiSummary || 'Situation details unavailable.',
      missionObjective:     'Respond immediately and assess on-site.',
      immediateActions:     ['Deploy nearest unit', 'Establish command post', 'Assess casualties', 'Secure perimeter'],
      resourcesNeeded:      ['Emergency response unit', 'Medical team'],
      safetyConsiderations: ['Unknown hazards — proceed with caution'],
      estimatedImpact:      'Unknown — on-site assessment required',
      generatedAt:          new Date().toISOString(),
    };
  }
}

export default genAI;
