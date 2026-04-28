import { GoogleGenAI } from '@google/genai';

// =============================================================
// GEMINI AI CONFIG
// Uses the @google/genai SDK (stable v1 API)
// Model fallback chain: 2.0-flash → 1.5-flash → 1.5-flash-8b
// Retries up to 2 times on 429 quota errors with backoff.
// =============================================================
const GEMINI_KEY = process.env.GEMINI_API_KEY || '';

// Validate key at startup — catches misconfigured Cloud Run envs early
if (!GEMINI_KEY) {
  console.error('🔴 [AI] GEMINI_API_KEY is not set! AI triage will use fallback responses.');
} else if (!GEMINI_KEY.startsWith('AIza')) {
  console.warn('🟡 [AI] GEMINI_API_KEY may be invalid (expected format: AIza...). AI triage may fail.');
} else {
  console.log('✅ [AI] Gemini API key loaded successfully.');
}

const genAI = new GoogleGenAI({ apiKey: GEMINI_KEY });

// Model fallback chain — if the primary model is quota-limited, try the next
// Correct model IDs from the API — verified via /v1beta/models endpoint
const MODEL_CHAIN = ['gemini-2.0-flash', 'gemini-2.0-flash-lite', 'gemini-2.5-flash'];

// =============================================================
// HELPER: generateWithFallback
// Tries each model in MODEL_CHAIN. On 429 / quota error, waits
// briefly and tries the next model. Returns the text result or
// throws if ALL models fail.
// =============================================================
async function generateWithFallback(prompt: string): Promise<string> {
  for (let modelIdx = 0; modelIdx < MODEL_CHAIN.length; modelIdx++) {
    const model = MODEL_CHAIN[modelIdx];
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const result = await genAI.models.generateContent({
          model,
          contents: prompt,
          config: { responseMimeType: 'application/json' },
        });
        const text = result.text || '{}';
        console.log(`✅ [AI] Generated with model: ${model}`);
        return text;
      } catch (err) {
        const msg = (err as Error).message || String(err);
        const isQuota    = msg.includes('429') || msg.toLowerCase().includes('quota') || msg.toLowerCase().includes('rate') || msg.toLowerCase().includes('resource_exhausted');
        const isDailyOut = msg.toLowerCase().includes('perday') || msg.toLowerCase().includes('per_day') || msg.toLowerCase().includes('daily');
        const isModelErr = msg.includes('404') || msg.toLowerCase().includes('not found') || msg.toLowerCase().includes('invalid model');

        if (isModelErr) {
          // This model doesn't exist / isn't available — skip to next immediately
          console.warn(`🟡 [AI] Model ${model} unavailable (${msg.slice(0, 80)}), trying next...`);
          break;
        }

        if (isQuota && isDailyOut) {
          // Daily quota fully exhausted — no point retrying this model
          console.warn(`🟡 [AI] Model ${model} daily quota exhausted, falling back immediately...`);
          break;
        }

        if (isQuota && attempt === 0) {
          // Per-minute quota — wait 32s (API-recommended retryDelay) and retry once
          console.warn(`🟡 [AI] Model ${model} rate-limited (429), retrying in 32s...`);
          await new Promise(r => setTimeout(r, 32000));
          continue;
        }

        if (isQuota && modelIdx < MODEL_CHAIN.length - 1) {
          // Second attempt also quota — move to next model
          console.warn(`🟡 [AI] Model ${model} still quota-limited, falling back to ${MODEL_CHAIN[modelIdx + 1]}...`);
          break;
        }

        // Non-quota error — log fully and throw
        console.error(`🔴 [AI] Model ${model} error (attempt ${attempt + 1}): ${msg}`);
        throw err;
      }
    }
  }
  throw new Error('All Gemini models quota-limited or unavailable');
}

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
// RULE-BASED TRIAGE (Offline Fallback)
// Keyword-based classifier used when Gemini quota is exhausted.
// Provides meaningful triage without AI, marked with lower confidence.
// =============================================================
function ruleBasedTriage(message: string): TriageResult {
  const m = message.toLowerCase();

  // Rule table: [keywords, type, severity, summary, actions]
  type RuleRow = [string[], string, TriageResult['severity'], string, string[]];
  const rules: RuleRow[] = [
    [
      ['fire', 'blaze', 'burning', 'smoke', 'flames', 'arson'],
      'Fire', 'CRITICAL',
      'Active fire reported. Immediate evacuation and fire suppression response required.',
      ['Dispatch fire brigade immediately', 'Evacuate all occupants', 'Establish 50m safety perimeter', 'Alert nearby units'],
    ],
    [
      ['flood', 'flooding', 'submerged', 'waterlogged', 'inundated', 'deluge', 'overflow'],
      'Flood', 'HIGH',
      'Flooding reported in the area. Water rescue and evacuation may be required.',
      ['Deploy water rescue teams', 'Evacuate low-lying zones', 'Alert disaster management authority', 'Monitor water levels'],
    ],
    [
      ['earthquake', 'tremor', 'shaking', 'quake', 'seismic', 'aftershock'],
      'Earthquake', 'CRITICAL',
      'Seismic activity reported. Structural damage and casualties likely. Immediate response required.',
      ['Search and rescue operations', 'Check structural integrity of buildings', 'Establish medical triage', 'Deploy NDRF teams'],
    ],
    [
      ['gas', 'leak', 'lpg', 'pipeline', 'fumes', 'smell', 'chemical'],
      'Gas Leak', 'HIGH',
      'Hazardous gas or chemical leak reported. Evacuation and containment required immediately.',
      ['Evacuate 100m radius', 'Cut gas supply at main valve', 'No open flames or electrical switches', 'Notify hazmat team'],
    ],
    [
      ['collapse', 'building fell', 'structure', 'debris', 'rubble', 'cave'],
      'Structural Collapse', 'CRITICAL',
      'Structural collapse reported with possible trapped victims. Urban search and rescue required.',
      ['Deploy urban search and rescue', 'Establish incident command post', 'Medical standby for casualties', 'Cordon area for aftershock risk'],
    ],
    [
      ['accident', 'crash', 'collision', 'vehicle', 'car', 'truck', 'hit', 'ram'],
      'Accident', 'HIGH',
      'Traffic accident reported. Emergency medical services and road clearance required.',
      ['Dispatch EMS immediately', 'Clear road for emergency access', 'Manage traffic diversion', 'Assess for fuel leak or fire risk'],
    ],
    [
      ['medical', 'heart', 'unconscious', 'breathe', 'breathing', 'chest', 'stroke', 'seizure', 'collapsed', 'injured', 'wound'],
      'Medical', 'CRITICAL',
      'Medical emergency reported. Immediate paramedic response and first aid required.',
      ['Dispatch ambulance immediately', 'Guide bystanders to begin CPR if needed', 'Clear path for emergency vehicle', 'Alert nearest hospital'],
    ],
    [
      ['violence', 'attack', 'assault', 'shooting', 'stabbing', 'weapon', 'fight', 'riot', 'threat'],
      'Violence', 'CRITICAL',
      'Violent incident in progress. Immediate law enforcement and medical response required.',
      ['Dispatch police immediately', 'Secure the perimeter', 'Do not enter without law enforcement', 'EMS on standby'],
    ],
    [
      ['missing', 'lost', 'child', 'person', 'disappeared', 'cannot find'],
      'Missing Person', 'MODERATE',
      'Missing person report filed. Search and coordination with local authorities required.',
      ['File missing person report with police', 'Coordinate search party', 'Alert nearby areas', 'Check CCTV footage'],
    ],
  ];

  for (const [keywords, type, severity, summary, actions] of rules) {
    if (keywords.some(kw => m.includes(kw))) {
      return {
        incidentType:       type,
        severity,
        confidence:         65, // Lower confidence for rule-based
        summary,
        recommendedActions: actions,
      };
    }
  }

  // Generic fallback (still better than "unavailable")
  return {
    incidentType:       'Unknown',
    severity:           'HIGH',
    confidence:         40,
    summary:            `Emergency situation reported requiring immediate response. Details: "${message.slice(0, 80)}${message.length > 80 ? '...' : ''}"`,
    recommendedActions: ['Dispatch nearest response unit', 'Assess situation on-site', 'Establish communication with reporter', 'Escalate if life-threatening'],
  };
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
    const text  = await generateWithFallback(prompt);
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
    const msg = (err as Error).message || String(err);
    const isQuota = msg.includes('429') || msg.toLowerCase().includes('quota') || msg.toLowerCase().includes('rate') || msg.toLowerCase().includes('resource_exhausted');
    if (isQuota) {
      console.warn('🟡 [AI] ALL models quota-limited — using rule-based triage fallback.');
    } else {
      console.error('🔴 [AI] Triage failed:', msg, '— using rule-based triage fallback.');
    }
    // Degrade gracefully: keyword triage instead of dead fallback text
    return ruleBasedTriage(message);
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
    const text   = await generateWithFallback(prompt);
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
