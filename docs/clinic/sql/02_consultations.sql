-- ============================================================
-- mantrasdb | Módulo Clinic
-- Archivo: 02_consultations.sql
-- Descripción: Consultas médicas y todo lo que ocurre en ellas:
--              signos vitales, diagnósticos, recetas, laboratorio,
--              imágenes, vacunas, cirugías y registros externos.
--
-- Tablas:
--    8. consultations          — Consulta/visita médica
--    9. vital_signs            — Signos vitales por consulta (INMUTABLE)
--   10. consultation_diagnoses — Diagnósticos ICD-10 por consulta (INMUTABLE)
--   11. prescriptions          — Receta médica
--   12. prescription_lines     — Medicamentos de la receta (INMUTABLE)
--   13. lab_orders             — Solicitudes de laboratorio
--   14. lab_results            — Resultados de laboratorio (INMUTABLE)
--   15. imaging_studies        — Estudios de imagen (Rx, ecografía, MRI)
--   16. vaccinations           — Registro de vacunas
--   17. surgeries              — Procedimientos quirúrgicos
--   18. external_records       — Historial de otros centros médicos
--
-- Vistas:
--   clinic.patient_timeline_view       — Historia cronológica completa
--   clinic.active_medications_view     — Medicamentos actuales activos
--   clinic.vaccination_calendar_view   — Vacunas aplicadas y próximas
--   clinic.pending_results_view        — Laboratorios sin resultado
--
-- ALTER TABLE:
--   Completa FK patient_allergies.consultation_id → consultations
-- ============================================================

-- ============================================================
-- 8. CONSULTATIONS — Consulta o visita médica
--    Es el núcleo del expediente clínico.
-- ============================================================
CREATE TABLE clinic.consultations (
    id                  BIGSERIAL   PRIMARY KEY,
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Vinculo con el módulo de agenda (opcional)
    appointment_id      BIGINT      REFERENCES services.appointments(id),

    -- Médico/veterinario que atiende
    attending_staff_id  BIGINT      REFERENCES hr.employees(id),

    -- Tipo de consulta
    consultation_type   VARCHAR(30)  NOT NULL DEFAULT 'outpatient',
    -- outpatient    : consulta ambulatoria (la más común)
    -- emergency     : urgencias
    -- follow_up     : control post-tratamiento
    -- preventive    : chequeo preventivo / vacunación
    -- telemedicine  : teleconsulta
    -- home_visit    : visita domiciliaria
    -- hospitalization: hospitalización (puede durar varios días)
    -- surgery_prep  : evaluación pre-quirúrgica

    -- Especialidad médica
    specialty           VARCHAR(100),
    -- Ej: "Medicina General", "Cardiología", "Dermatología",
    --     "Medicina Interna Veterinaria", "Cirugía Veterinaria"

    -- Fecha y hora de la consulta
    consulted_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- Duración en minutos
    duration_min        SMALLINT,

    -- ── ANAMNESIS / MOTIVO DE CONSULTA ──────────────────────
    chief_complaint     TEXT,
    -- Motivo de consulta en palabras del paciente/dueño
    -- Ej: "Lleva 3 días con fiebre y tos", "No come desde ayer"

    history_of_illness  TEXT,
    -- Historia de la enfermedad actual (HEA)
    -- Narración del médico sobre el cuadro clínico

    -- ── EXAMEN FÍSICO ───────────────────────────────────────
    physical_exam       TEXT,
    -- Hallazgos del examen físico completo

    -- ── EVALUACIÓN Y PLAN ───────────────────────────────────
    assessment          TEXT,
    -- Impresión diagnóstica / evaluación clínica

    treatment_plan      TEXT,
    -- Plan de tratamiento indicado

    -- ── INDICACIONES AL ALTA ────────────────────────────────
    discharge_instructions TEXT,
    -- Indicaciones para el paciente/dueño al salir

    -- ── SEGUIMIENTO ─────────────────────────────────────────
    follow_up_required  BOOLEAN     NOT NULL DEFAULT FALSE,
    follow_up_in_days   SMALLINT,
    follow_up_notes     VARCHAR(300),

    -- ── ESTADO DE LA CONSULTA ───────────────────────────────
    status              VARCHAR(20)  NOT NULL DEFAULT 'in_progress',
    -- in_progress / completed / cancelled / no_show

    -- ── HOSPITALIZACIÓN (si aplica) ─────────────────────────
    -- Fechas de internamiento para hospitalization type
    admitted_at         TIMESTAMPTZ,
    discharged_at       TIMESTAMPTZ,
    ward                VARCHAR(100),
    -- Ej: "UCI", "Pediatría", "Cirugía"
    bed_number          VARCHAR(20),

    -- ── FACTURACIÓN ─────────────────────────────────────────
    invoice_id          BIGINT      REFERENCES sales.invoices(id),

    -- ¿Fue cubierta por seguro?
    insurance_id        BIGINT      REFERENCES clinic.patient_insurance(id),
    insurance_auth_code VARCHAR(50),

    internal_notes      TEXT,
    -- Notas internas (no visibles para el paciente)

    completed_at        TIMESTAMPTZ,
    completed_by        BIGINT      REFERENCES hr.system_users(id),

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_consult_patient   ON clinic.consultations (patient_id, consulted_at DESC);
CREATE INDEX idx_consult_staff     ON clinic.consultations (attending_staff_id, consulted_at DESC);
CREATE INDEX idx_consult_appt      ON clinic.consultations (appointment_id) WHERE appointment_id IS NOT NULL;
CREATE INDEX idx_consult_status    ON clinic.consultations (status, company_id);
CREATE TRIGGER trg_consult_upd BEFORE UPDATE ON clinic.consultations
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.consultations IS
'Consulta médica o veterinaria. Núcleo del expediente clínico: motivo, examen físico, plan de tratamiento, indicaciones y seguimiento. Se vincula con services.appointments.';

-- ============================================================
-- FK diferida: patient_allergies.consultation_id → consultations
-- (consultations recién creada arriba)
-- ============================================================
ALTER TABLE clinic.patient_allergies
    ADD CONSTRAINT fk_allergy_consultation
    FOREIGN KEY (consultation_id) REFERENCES clinic.consultations(id);

-- ============================================================
-- 9. VITAL_SIGNS — Signos vitales por consulta
--    INMUTABLE: snapshot fisiológico en el momento de la consulta.
-- ============================================================
CREATE TABLE clinic.vital_signs (
    id                  BIGSERIAL   PRIMARY KEY,
    consultation_id     BIGINT      NOT NULL REFERENCES clinic.consultations(id),
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    measured_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- Temperatura corporal (°C)
    temperature_c       NUMERIC(4,1),
    -- Humanos: 36.5–37.5 normal / Perros: 38.0–39.2 normal

    -- Presión arterial (mmHg)
    bp_systolic         SMALLINT,
    bp_diastolic        SMALLINT,
    -- Ej: 120 / 80

    -- Frecuencia cardíaca (lpm)
    heart_rate          SMALLINT,

    -- Frecuencia respiratoria (rpm)
    respiratory_rate    SMALLINT,

    -- Saturación de oxígeno (%)
    oxygen_saturation   NUMERIC(4,1),

    -- Peso (kg) — importante para dosificación en vet y seguimiento
    weight_kg           NUMERIC(8,3),

    -- Talla/altura (cm) — principalmente humanos
    height_cm           NUMERIC(5,1),

    -- IMC calculado automáticamente (solo si weight y height presentes)
    bmi                 NUMERIC(5,2) GENERATED ALWAYS AS (
        CASE
            WHEN weight_kg IS NOT NULL AND height_cm IS NOT NULL AND height_cm > 0
            THEN ROUND((weight_kg / ((height_cm / 100.0) ^ 2))::NUMERIC, 2)
            ELSE NULL
        END
    ) STORED,

    -- Glucemia (mg/dL)
    blood_glucose       NUMERIC(6,1),

    -- Dolor (escala 0-10)
    pain_scale          SMALLINT,
    -- 0 = sin dolor, 10 = dolor máximo

    -- Nivel de conciencia
    consciousness_level VARCHAR(20),
    -- alert / verbal / pain / unresponsive (AVPU)

    -- Para veterinaria: condición corporal (1-9 BCS)
    body_condition_score SMALLINT,

    -- Mucosas (veterinaria)
    mucous_membranes    VARCHAR(50),
    -- Ej: "Rosadas y húmedas", "Pálidas", "Ictéricas"

    notes               TEXT,

    measured_by         BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_vitals_consult  ON clinic.vital_signs (consultation_id);
CREATE INDEX idx_vitals_patient  ON clinic.vital_signs (patient_id, measured_at DESC);
COMMENT ON TABLE clinic.vital_signs IS
'Signos vitales por consulta: temperatura, presión arterial, FC, peso, talla, IMC (GENERATED), glucemia. Válido para humanos y animales. INMUTABLE.';

-- ============================================================
-- 10. CONSULTATION_DIAGNOSES — Diagnósticos por consulta
--     INMUTABLE: el diagnóstico registrado queda permanente.
--     Soporta ICD-10 (humanos) y códigos libres (vet).
-- ============================================================
CREATE TABLE clinic.consultation_diagnoses (
    id                  BIGSERIAL   PRIMARY KEY,
    consultation_id     BIGINT      NOT NULL REFERENCES clinic.consultations(id),
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Código diagnóstico (ICD-10 para humanos, libre para vet)
    diagnosis_code      VARCHAR(20),
    -- ICD-10: "J06.9" (IRA), "E11" (DM2), "K29.5" (Gastritis)
    -- Vet: "CDAD", "Parvovirosis", "Distemper"

    -- Descripción completa
    diagnosis_name      VARCHAR(500) NOT NULL,
    -- Ej: "Diabetes Mellitus tipo 2 sin complicaciones"

    -- Sistema de codificación
    coding_system       VARCHAR(20)  NOT NULL DEFAULT 'icd10',
    -- icd10 / ciap2 / snomed / vet_free / free_text

    -- Tipo de diagnóstico
    diagnosis_type      VARCHAR(20)  NOT NULL DEFAULT 'definitive',
    -- presumptive   : diagnóstico presuntivo (pendiente confirmar)
    -- definitive    : diagnóstico definitivo
    -- differential  : diagnóstico diferencial (descartado o en evaluación)
    -- chronic       : enfermedad crónica de base (ya conocida)
    -- complication  : complicación de otra enfermedad

    -- ¿Es el diagnóstico principal?
    is_primary          BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Lateralidad (si aplica)
    laterality          VARCHAR(10),
    -- left / right / bilateral / not_applicable

    -- ¿Diagnóstico nuevo o seguimiento de uno previo?
    is_new_diagnosis    BOOLEAN     NOT NULL DEFAULT TRUE,

    notes               TEXT,

    diagnosed_by        BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_diag_consult   ON clinic.consultation_diagnoses (consultation_id);
CREATE INDEX idx_diag_patient   ON clinic.consultation_diagnoses (patient_id, created_at DESC);
CREATE INDEX idx_diag_code      ON clinic.consultation_diagnoses (diagnosis_code) WHERE diagnosis_code IS NOT NULL;
COMMENT ON TABLE clinic.consultation_diagnoses IS
'Diagnósticos por consulta. Soporta ICD-10 (clínica humana) y texto libre (veterinaria). Múltiples diagnósticos por consulta (principal + diferenciales). INMUTABLE.';

-- ============================================================
-- 11. PRESCRIPTIONS — Receta médica
--     Cabecera de la receta emitida en una consulta.
-- ============================================================
CREATE TABLE clinic.prescriptions (
    id                  BIGSERIAL   PRIMARY KEY,
    consultation_id     BIGINT      NOT NULL REFERENCES clinic.consultations(id),
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Médico prescriptor
    prescribed_by       BIGINT      REFERENCES hr.employees(id),

    prescription_number VARCHAR(50)  NOT NULL,
    -- Número único de la receta (para farmacia)

    prescription_type   VARCHAR(20)  NOT NULL DEFAULT 'standard',
    -- standard      : receta común
    -- controlled    : medicamento controlado (requiere receta especial)
    -- electronic    : receta electrónica

    issued_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    valid_until         DATE,

    -- ¿Fue dispensada en farmacia propia?
    dispensed_internally BOOLEAN     NOT NULL DEFAULT FALSE,
    dispensed_at        TIMESTAMPTZ,

    -- Observaciones para el farmacéutico
    pharmacist_notes    TEXT,

    status              VARCHAR(20)  NOT NULL DEFAULT 'active',
    -- active / dispensed / cancelled / expired

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_prescription_number ON clinic.prescriptions (company_id, prescription_number);
CREATE INDEX idx_rx_consult  ON clinic.prescriptions (consultation_id);
CREATE INDEX idx_rx_patient  ON clinic.prescriptions (patient_id, issued_at DESC);
CREATE TRIGGER trg_rx_upd BEFORE UPDATE ON clinic.prescriptions
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.prescriptions IS
'Receta médica emitida en una consulta. Tiene número único, tipo (común/controlada/electrónica) y estado.';

-- ============================================================
-- 12. PRESCRIPTION_LINES — Medicamentos de la receta
--     INMUTABLE: cada línea es un medicamento prescrito.
-- ============================================================
CREATE TABLE clinic.prescription_lines (
    id                  BIGSERIAL   PRIMARY KEY,
    prescription_id     BIGINT      NOT NULL REFERENCES clinic.prescriptions(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Número de línea
    line_number         SMALLINT    NOT NULL DEFAULT 1,

    -- Medicamento
    drug_name           VARCHAR(300) NOT NULL,
    -- Nombre genérico + concentración: "Amoxicilina 500mg cápsulas"

    -- Principio activo
    active_ingredient   VARCHAR(200),
    -- "Amoxicilina"

    -- Forma farmacéutica
    dosage_form         VARCHAR(50),
    -- Tableta / Cápsula / Jarabe / Inyectable / Crema / Gotas / Óvulo

    -- Concentración
    concentration       VARCHAR(50),
    -- "500mg" / "250mg/5ml" / "1%" / "0.1mg"

    -- Vía de administración
    route               VARCHAR(30)  NOT NULL DEFAULT 'oral',
    -- oral / topical / inhalation / intravenous / intramuscular /
    -- subcutaneous / ophthalmic / otic / rectal / sublingual

    -- Dosis
    dose                VARCHAR(100) NOT NULL,
    -- "1 tableta" / "5ml" / "2 gotas en cada ojo"

    -- Frecuencia
    frequency           VARCHAR(100) NOT NULL,
    -- "Cada 8 horas" / "Una vez al día" / "Con las comidas"

    -- Duración del tratamiento
    duration            VARCHAR(100),
    -- "7 días" / "14 días" / "Uso crónico — no suspender"

    -- Cantidad total a dispensar
    quantity            NUMERIC(8,2),
    unit                VARCHAR(30),
    -- "tabletas" / "ml" / "unidades"

    -- Instrucciones especiales
    special_instructions VARCHAR(300),
    -- "Tomar con bastante agua", "Mantener en refrigeración"

    -- ¿Medicamento del stock de la clínica? (vinculo con inventario)
    product_id          BIGINT      REFERENCES logistics.products(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_rxline_prescription ON clinic.prescription_lines (prescription_id);
COMMENT ON TABLE clinic.prescription_lines IS
'Línea de medicamento en una receta. INMUTABLE. Incluye dosis, frecuencia, duración y vía de administración. Puede vincular al inventario de la clínica.';

-- ============================================================
-- 13. LAB_ORDERS — Solicitudes de laboratorio / paraclínicos
-- ============================================================
CREATE TABLE clinic.lab_orders (
    id                  BIGSERIAL   PRIMARY KEY,
    consultation_id     BIGINT      NOT NULL REFERENCES clinic.consultations(id),
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    ordered_by          BIGINT      REFERENCES hr.employees(id),
    ordered_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- Tipo de examen
    order_type          VARCHAR(30)  NOT NULL DEFAULT 'laboratory',
    -- laboratory   : análisis de sangre, orina, heces, cultivos
    -- pathology    : biopsia, citología, histología
    -- microbiology : cultivo y antibiograma

    -- Descripción del panel/prueba
    panel_name          VARCHAR(200) NOT NULL,
    -- Ej: "Hemograma completo + PCR", "Perfil lipídico", "Cultivo de orina"

    -- Exámenes individuales
    tests_requested     TEXT,
    -- JSON o texto con lista de exámenes: "Hemoglobina, Hematocrito, Leucocitos..."

    -- Diagnóstico de referencia (para el laboratorio)
    clinical_indication VARCHAR(300),

    -- Estado
    status              VARCHAR(20)  NOT NULL DEFAULT 'ordered',
    -- ordered / sample_collected / processing / completed / cancelled

    -- ¿El laboratorio es externo?
    lab_name            VARCHAR(200),
    -- NULL si se procesa internamente
    -- "Laboratorios Roe", "Suiza Lab", "Synlab"

    -- Fecha de toma de muestra
    sample_collected_at TIMESTAMPTZ,

    -- Fecha esperada de resultados
    expected_results_at TIMESTAMPTZ,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_laborder_consult ON clinic.lab_orders (consultation_id);
CREATE INDEX idx_laborder_patient ON clinic.lab_orders (patient_id, ordered_at DESC);
CREATE INDEX idx_laborder_status  ON clinic.lab_orders (status, company_id);
CREATE TRIGGER trg_laborder_upd BEFORE UPDATE ON clinic.lab_orders
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.lab_orders IS
'Solicitud de laboratorio / paraclínico ordenado en una consulta. Soporta laboratorios internos y externos.';

-- ============================================================
-- 14. LAB_RESULTS — Resultados de laboratorio
--     INMUTABLE: los resultados quedan registrados para siempre.
-- ============================================================
CREATE TABLE clinic.lab_results (
    id                  BIGSERIAL   PRIMARY KEY,
    lab_order_id        BIGINT      NOT NULL REFERENCES clinic.lab_orders(id),
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Examen individual dentro del panel
    test_name           VARCHAR(200) NOT NULL,
    -- "Hemoglobina", "Glucosa en ayunas", "TSH", "Creatinina"

    -- Resultado
    result_value        VARCHAR(100),
    -- "12.5" / "120" / "POSITIVO" / "Negativo" / "Resistente"

    result_unit         VARCHAR(30),
    -- "g/dL" / "mg/dL" / "mUI/L" / "UFC/mL"

    -- Valores de referencia del laboratorio
    reference_min       VARCHAR(50),
    reference_max       VARCHAR(50),
    reference_text      VARCHAR(200),
    -- Para resultados cualitativos: "Negativo" o "< 5"

    -- ¿Está fuera de rango?
    is_abnormal         BOOLEAN     NOT NULL DEFAULT FALSE,
    abnormal_flag       VARCHAR(5),
    -- H (high) / L (low) / HH (critically high) / LL (critically low)

    -- Comentarios del laboratorio
    lab_comments        TEXT,

    -- Archivo PDF del resultado
    result_file_url     VARCHAR(500),

    received_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    verified_by         BIGINT      REFERENCES hr.system_users(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_labresult_order   ON clinic.lab_results (lab_order_id);
CREATE INDEX idx_labresult_patient ON clinic.lab_results (patient_id, received_at DESC);
CREATE INDEX idx_labresult_abnorm  ON clinic.lab_results (patient_id, is_abnormal)
    WHERE is_abnormal = TRUE;
COMMENT ON TABLE clinic.lab_results IS
'Resultado individual de laboratorio. INMUTABLE. Incluye valor, unidad, rango de referencia, flag de anormalidad y URL del PDF del laboratorio.';

-- ============================================================
-- 15. IMAGING_STUDIES — Estudios de imagen
--     Radiografías, ecografías, tomografías, resonancias, etc.
-- ============================================================
CREATE TABLE clinic.imaging_studies (
    id                  BIGSERIAL   PRIMARY KEY,
    consultation_id     BIGINT      NOT NULL REFERENCES clinic.consultations(id),
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    ordered_by          BIGINT      REFERENCES hr.employees(id),

    -- Tipo de estudio
    study_type          VARCHAR(30)  NOT NULL DEFAULT 'xray',
    -- xray        : radiografía
    -- ultrasound  : ecografía / ultrasonido
    -- ct          : tomografía computarizada (TC)
    -- mri         : resonancia magnética (RM)
    -- endoscopy   : endoscopía
    -- echocardiography: ecocardiograma
    -- mammography : mamografía
    -- other

    -- Región/área estudiada
    body_region         VARCHAR(150),
    -- Ej: "Tórax PA y Lateral", "Abdomen total", "Columna lumbar"

    -- Indicación clínica
    clinical_indication VARCHAR(300),

    -- Institución donde se realizó
    imaging_center      VARCHAR(200),
    -- NULL si se realizó aquí
    -- "Diagnóstico por Imágenes Miraflores"

    study_date          DATE        NOT NULL DEFAULT CURRENT_DATE,

    -- Informe del radiólogo
    radiologist_name    VARCHAR(200),
    findings            TEXT,
    -- "Se observa opacidad en base pulmonar derecha..."
    impression          TEXT,
    -- Conclusión/impresión diagnóstica del radiólogo

    -- URLs de imágenes (DICOM viewer, fotos, etc.)
    image_url           VARCHAR(500),
    report_file_url     VARCHAR(500),

    status              VARCHAR(20)  NOT NULL DEFAULT 'ordered',
    -- ordered / performed / reported / reviewed

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_imaging_consult ON clinic.imaging_studies (consultation_id);
CREATE INDEX idx_imaging_patient ON clinic.imaging_studies (patient_id, study_date DESC);
CREATE TRIGGER trg_imaging_upd BEFORE UPDATE ON clinic.imaging_studies
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.imaging_studies IS
'Estudios de imagen: Rx, ecografía, TC, RM, ecocardiograma. Guarda hallazgos, impresión diagnóstica y URLs de imágenes/informes.';

-- ============================================================
-- 16. VACCINATIONS — Registro de vacunas aplicadas
-- ============================================================
CREATE TABLE clinic.vaccinations (
    id                  BIGSERIAL   PRIMARY KEY,
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Si la vacuna se aplicó en una consulta nuestra
    consultation_id     BIGINT      REFERENCES clinic.consultations(id),

    -- Nombre de la vacuna
    vaccine_name        VARCHAR(200) NOT NULL,
    -- Ej: "Vacuna 8 en 1 (Distemper, Parvo, Hepatitis...)",
    --     "Antirrábica", "Influenza estacional", "COVID-19 BNT162b2"

    -- Laboratorio fabricante
    manufacturer        VARCHAR(200),
    -- Ej: "Zoetis", "MSD Animal Health", "Pfizer", "Sanofi"

    -- Lote y vencimiento del vial
    lot_number          VARCHAR(50),
    expiry_date         DATE,

    -- Número de dosis en el esquema de vacunación
    dose_number         SMALLINT    NOT NULL DEFAULT 1,
    -- 1 = primera dosis, 2 = segunda dosis, 3 = refuerzo

    -- Vía y sitio de aplicación
    route               VARCHAR(30)  NOT NULL DEFAULT 'subcutaneous',
    -- subcutaneous / intramuscular / intranasal / oral
    injection_site      VARCHAR(100),
    -- "Músculo glúteo derecho", "Subcutáneo zona escapular"

    applied_at          DATE        NOT NULL DEFAULT CURRENT_DATE,
    applied_by          BIGINT      REFERENCES hr.employees(id),

    -- Próxima dosis / refuerzo
    next_dose_due       DATE,
    -- Calculado por la app o ingresado manualmente

    -- ¿Fue aplicada aquí o registrada de documento externo?
    applied_here        BOOLEAN     NOT NULL DEFAULT TRUE,
    external_institution VARCHAR(200),

    -- Reacción adversa (si hubo)
    adverse_reaction    VARCHAR(300),

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_vaccine_patient ON clinic.vaccinations (patient_id, applied_at DESC);
CREATE INDEX idx_vaccine_due     ON clinic.vaccinations (next_dose_due, company_id)
    WHERE next_dose_due IS NOT NULL;
CREATE TRIGGER trg_vaccine_upd BEFORE UPDATE ON clinic.vaccinations
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.vaccinations IS
'Registro de vacunas aplicadas o documentadas de cartilla externa. Incluye lote, vencimiento, próxima dosis y control de reacciones adversas.';

-- ============================================================
-- 17. SURGERIES — Procedimientos quirúrgicos
-- ============================================================
CREATE TABLE clinic.surgeries (
    id                  BIGSERIAL   PRIMARY KEY,
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    consultation_id     BIGINT      REFERENCES clinic.consultations(id),

    -- Nombre del procedimiento
    procedure_name      VARCHAR(300) NOT NULL,
    -- Ej: "Ovariohisterectomía", "Apendicectomía laparoscópica",
    --     "Extracción de masa subcutánea", "Cesárea"

    -- Código CPT / CIAP (para clínicas humanas)
    procedure_code      VARCHAR(20),

    -- Tipo de anestesia
    anesthesia_type     VARCHAR(30)  NOT NULL DEFAULT 'general',
    -- general / local / regional / sedation / none

    -- Anestesista
    anesthesiologist_id BIGINT      REFERENCES hr.employees(id),

    -- Cirujano principal
    surgeon_id          BIGINT      REFERENCES hr.employees(id),

    -- Sala quirúrgica
    operating_room      VARCHAR(50),

    -- Fechas
    scheduled_at        TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ,

    -- Duración total
    duration_min        SMALLINT    GENERATED ALWAYS AS (
        CASE
            WHEN started_at IS NOT NULL AND ended_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (ended_at - started_at)) / 60
            ELSE NULL
        END::SMALLINT
    ) STORED,

    -- Estado
    status              VARCHAR(20)  NOT NULL DEFAULT 'scheduled',
    -- scheduled / in_progress / completed / cancelled / aborted

    -- Hallazgos intraoperatorios
    intraoperative_findings TEXT,

    -- Complicaciones
    complications       TEXT,

    -- Reporte operatorio
    operative_report    TEXT,

    -- Diagnóstico post-quirúrgico
    postop_diagnosis    VARCHAR(300),

    -- Plan post-operatorio
    postop_instructions TEXT,

    notes               TEXT,

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_surgery_patient ON clinic.surgeries (patient_id, scheduled_at DESC);
CREATE INDEX idx_surgery_status  ON clinic.surgeries (status, company_id);
CREATE TRIGGER trg_surgery_upd BEFORE UPDATE ON clinic.surgeries
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.surgeries IS
'Procedimiento quirúrgico. Incluye cirujano, anestesista, sala, duración (GENERATED), hallazgos, complicaciones y reporte operatorio.';

-- ============================================================
-- 18. EXTERNAL_RECORDS — Historial médico de otros centros
--     CLAVE DEL MÓDULO: permite documentar todo lo que el
--     paciente se ha atendido en otro lugar para tener un
--     historial clínico centralizado y completo.
-- ============================================================
CREATE TABLE clinic.external_records (
    id                  BIGSERIAL   PRIMARY KEY,
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Tipo de registro externo
    record_type         VARCHAR(30)  NOT NULL DEFAULT 'consultation',
    -- consultation      : consulta en otro centro
    -- hospitalization   : hospitalización en otro hospital
    -- surgery           : cirugía realizada en otro centro
    -- lab_result        : resultado de lab de otro laboratorio
    -- imaging           : estudio de imagen de otro centro
    -- vaccination       : vacuna registrada de cartilla externa
    -- prescription      : receta de otro médico
    -- specialist_report : informe de especialista externo
    -- discharge_summary : epicrisis / resumen de alta hospitalaria
    -- emergency_care    : atención de urgencias en otro centro

    -- Institución donde fue atendido
    institution_name    VARCHAR(300) NOT NULL,
    -- Ej: "Hospital Nacional Cayetano Heredia", "Clínica San Pablo",
    --     "Veterinaria San Borja", "Hospital Regional Cusco"

    institution_type    VARCHAR(20)  NOT NULL DEFAULT 'clinic',
    -- hospital / clinic / laboratory / emergency / pharmacy /
    -- specialist_office / vet_clinic / other

    -- País (por si fue en el extranjero)
    country_code        VARCHAR(3)   NOT NULL DEFAULT 'PER',

    -- Médico/veterinario que atendió (si se conoce)
    attending_physician VARCHAR(200),
    specialty           VARCHAR(100),

    -- Fecha de la atención
    record_date         DATE        NOT NULL,

    -- Diagnóstico registrado en ese centro
    diagnosis_recorded  VARCHAR(500),
    -- Ej: "Gastroenteritis aguda", "Fractura de radio izquierdo",
    --     "Dermatitis alérgica crónica"

    -- Código diagnóstico (si el documento lo trae)
    diagnosis_code      VARCHAR(20),

    -- Tratamiento o procedimiento realizado
    treatment_given     TEXT,
    -- Ej: "Hidratación IV por 48h, Metronidazol 500mg c/8h",
    --     "Cirugía de hernia inguinal", "Quimioterapia ciclo 1"

    -- Medicamentos prescritos (resumen)
    medications_prescribed TEXT,

    -- ¿Hay documentos adjuntos?
    has_documents       BOOLEAN     NOT NULL DEFAULT FALSE,
    document_urls       TEXT,
    -- JSON array con URLs de los PDFs escaneados / fotos

    -- Notas del médico de nuestro centro al revisar este registro
    review_notes        TEXT,
    reviewed_by         BIGINT      REFERENCES hr.system_users(id),
    reviewed_at         TIMESTAMPTZ,

    -- ¿Información confiable? (puede ser solo referida por el paciente)
    source_reliability  VARCHAR(20)  NOT NULL DEFAULT 'document',
    -- document      : verificado con documento físico/digital
    -- patient_report : referido verbalmente por el paciente/dueño
    -- system_import  : importado de otro sistema (HL7, FHIR)

    -- Si el paciente está pidiendo traslado o segunda opinión
    is_referral         BOOLEAN     NOT NULL DEFAULT FALSE,

    registered_by       BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_extern_patient ON clinic.external_records (patient_id, record_date DESC);
CREATE INDEX idx_extern_type    ON clinic.external_records (record_type, company_id);
CREATE TRIGGER trg_extern_upd BEFORE UPDATE ON clinic.external_records
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.external_records IS
'Historial médico de otros centros: consultas, hospitalizaciones, cirugías, labs, imágenes y vacunas de otras instituciones. Centraliza el historial clínico completo del paciente aunque haya sido atendido en otro lugar. Clave para análisis longitudinal.';

-- ============================================================
-- VISTA 1: Timeline completo del paciente
-- ============================================================
CREATE OR REPLACE VIEW clinic.patient_timeline_view AS

    -- Consultas propias
    SELECT
        p.id                                AS patient_id,
        p.company_id,
        COALESCE(p.full_name, p.animal_name) AS patient_display_name,
        p.patient_type,
        'consultation'                      AS event_type,
        c.consulted_at                      AS event_date,
        c.consultation_type                 AS subtype,
        c.chief_complaint                   AS description,
        c.status,
        c.id                                AS source_id,
        NULL::VARCHAR                       AS institution,
        TRUE                                AS is_internal
    FROM clinic.patients                p
    INNER JOIN clinic.consultations     c  ON c.patient_id = p.id

UNION ALL

    -- Diagnósticos
    SELECT
        p.id,
        p.company_id,
        COALESCE(p.full_name, p.animal_name),
        p.patient_type,
        'diagnosis',
        cd.created_at,
        cd.diagnosis_type,
        cd.diagnosis_name,
        'recorded',
        cd.id,
        NULL::VARCHAR,
        TRUE
    FROM clinic.patients                    p
    INNER JOIN clinic.consultation_diagnoses cd ON cd.patient_id = p.id

UNION ALL

    -- Cirugías
    SELECT
        p.id,
        p.company_id,
        COALESCE(p.full_name, p.animal_name),
        p.patient_type,
        'surgery',
        COALESCE(s.started_at, s.scheduled_at),
        s.status,
        s.procedure_name,
        s.status,
        s.id,
        NULL::VARCHAR,
        TRUE
    FROM clinic.patients    p
    INNER JOIN clinic.surgeries s ON s.patient_id = p.id

UNION ALL

    -- Vacunas
    SELECT
        p.id,
        p.company_id,
        COALESCE(p.full_name, p.animal_name),
        p.patient_type,
        'vaccination',
        v.applied_at::TIMESTAMPTZ,
        CASE WHEN v.applied_here THEN 'internal' ELSE 'external' END,
        v.vaccine_name,
        'applied',
        v.id,
        v.external_institution,
        v.applied_here
    FROM clinic.patients        p
    INNER JOIN clinic.vaccinations v ON v.patient_id = p.id

UNION ALL

    -- Registros externos
    SELECT
        p.id,
        p.company_id,
        COALESCE(p.full_name, p.animal_name),
        p.patient_type,
        'external_' || er.record_type,
        er.record_date::TIMESTAMPTZ,
        er.record_type,
        COALESCE(er.diagnosis_recorded, er.treatment_given),
        er.source_reliability,
        er.id,
        er.institution_name,
        FALSE
    FROM clinic.patients            p
    INNER JOIN clinic.external_records er ON er.patient_id = p.id

ORDER BY event_date DESC NULLS LAST;

COMMENT ON VIEW clinic.patient_timeline_view IS
'Historia clínica cronológica completa: consultas propias + diagnósticos + cirugías + vacunas + registros externos de otras instituciones. Todo en una vista.';

-- ============================================================
-- VISTA 2: Medicamentos activos (recetas vigentes)
-- ============================================================
CREATE OR REPLACE VIEW clinic.active_medications_view AS
SELECT
    p.id                                        AS patient_id,
    p.company_id,
    COALESCE(p.full_name, p.animal_name)         AS patient_display_name,
    p.patient_type,

    rx.id                                        AS prescription_id,
    rx.issued_at,
    rx.valid_until,

    c.consulted_at,
    c.specialty,

    rxl.drug_name,
    rxl.active_ingredient,
    rxl.dose,
    rxl.frequency,
    rxl.duration,
    rxl.route,
    rxl.special_instructions,

    -- ¿Sigue dentro del período?
    CASE
        WHEN rx.valid_until IS NULL THEN TRUE
        WHEN rx.valid_until >= CURRENT_DATE THEN TRUE
        ELSE FALSE
    END                                          AS is_current

FROM clinic.patients                p
INNER JOIN clinic.prescriptions     rx  ON rx.patient_id = p.id
                                       AND rx.status = 'active'
INNER JOIN clinic.consultations     c   ON c.id = rx.consultation_id
INNER JOIN clinic.prescription_lines rxl ON rxl.prescription_id = rx.id
ORDER BY p.id, rx.issued_at DESC;

COMMENT ON VIEW clinic.active_medications_view IS
'Medicamentos activos por paciente: todas las recetas vigentes con dosis, frecuencia y vía de administración. Útil para revisión pre-consulta.';

-- ============================================================
-- VISTA 3: Calendario de vacunas (aplicadas y próximas)
-- ============================================================
CREATE OR REPLACE VIEW clinic.vaccination_calendar_view AS
SELECT
    p.id                                        AS patient_id,
    p.company_id,
    COALESCE(p.full_name, p.animal_name)         AS patient_display_name,
    p.patient_type,

    v.vaccine_name,
    v.dose_number,
    v.applied_at,
    v.next_dose_due,
    v.applied_here,
    v.external_institution,
    v.adverse_reaction,
    v.lot_number,
    v.manufacturer,

    -- ¿La próxima dosis está vencida?
    CASE
        WHEN v.next_dose_due < CURRENT_DATE THEN 'overdue'
        WHEN v.next_dose_due BETWEEN CURRENT_DATE AND CURRENT_DATE + 30 THEN 'due_soon'
        WHEN v.next_dose_due > CURRENT_DATE + 30 THEN 'scheduled'
        ELSE 'no_next_dose'
    END                                          AS next_dose_status,

    -- Días hasta o desde la próxima dosis
    v.next_dose_due - CURRENT_DATE              AS days_to_next_dose

FROM clinic.patients            p
INNER JOIN clinic.vaccinations  v  ON v.patient_id = p.id
ORDER BY p.id, v.next_dose_due ASC NULLS LAST;

COMMENT ON VIEW clinic.vaccination_calendar_view IS
'Estado del calendario de vacunación: aplicadas, próximas dosis, vencidas y por vencer en los próximos 30 días. Para recordatorios automáticos en vet y clínica.';

-- ============================================================
-- VISTA 4: Laboratorios pendientes de resultado
-- ============================================================
CREATE OR REPLACE VIEW clinic.pending_results_view AS
SELECT
    p.id                                        AS patient_id,
    p.company_id,
    COALESCE(p.full_name, p.animal_name)         AS patient_display_name,

    lo.id                                        AS lab_order_id,
    lo.order_type,
    lo.panel_name,
    lo.lab_name,
    lo.ordered_at,
    lo.expected_results_at,
    lo.status,

    -- Días transcurridos desde la orden
    CURRENT_DATE - lo.ordered_at::DATE          AS days_waiting,

    -- ¿Está atrasado?
    CASE
        WHEN lo.expected_results_at IS NOT NULL
         AND lo.expected_results_at < NOW()
        THEN TRUE
        ELSE FALSE
    END                                          AS is_overdue

FROM clinic.patients        p
INNER JOIN clinic.lab_orders lo ON lo.patient_id = p.id
WHERE lo.status IN ('ordered', 'sample_collected', 'processing')
ORDER BY lo.ordered_at ASC;

COMMENT ON VIEW clinic.pending_results_view IS
'Exámenes de laboratorio sin resultado: ordenados, muestra tomada o en proceso. Incluye días de espera y alerta de atraso.';
