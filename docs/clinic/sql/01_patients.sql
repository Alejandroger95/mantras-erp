-- ============================================================
-- mantrasdb | Módulo Clinic
-- Archivo: 01_patients.sql
-- Descripción: Expediente clínico — pacientes, antecedentes,
--              alergias e historial externo.
--
-- Diseño genérico:
--   - Clínicas y hospitales (paciente humano)
--   - Veterinarias (paciente = animal, con dueño)
--   - El campo patient_type discrimina el caso
--
-- Se vincula con:
--   - hr.persons          (paciente humano ya registrado)
--   - sales.customers     (dueño del animal en veterinaria)
--   - services.appointments (la cita que originó la consulta)
--
-- Tablas:
--   1. species             — Catálogo de especies (para veterinaria)
--   2. breeds              — Catálogo de razas por especie
--   3. patients            — Paciente: humano o animal
--   4. patient_contacts    — Contactos de emergencia / dueño del animal
--   5. patient_background  — Antecedentes médicos crónicos
--   6. patient_allergies   — Alergias conocidas (INMUTABLE)
--   7. patient_insurance   — Seguro médico (para clínicas humanas)
-- ============================================================

CREATE SCHEMA IF NOT EXISTS clinic;

CREATE OR REPLACE FUNCTION clinic.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

-- ============================================================
-- 1. SPECIES — Catálogo de especies (principalmente para vet)
-- ============================================================
CREATE TABLE clinic.species (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(100) NOT NULL,
    -- Ej: "Perro", "Gato", "Ave", "Reptil", "Conejo", "Caballo", "Humano"

    name_scientific     VARCHAR(150),
    -- Ej: "Canis lupus familiaris"

    category            VARCHAR(30)  NOT NULL DEFAULT 'companion',
    -- companion   : mascota doméstica (perro, gato, hámster)
    -- exotic      : exóticos (reptil, ave, conejo)
    -- farm        : animales de granja (vaca, cerdo, oveja)
    -- equine      : caballos
    -- human       : para clínicas humanas

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    sort_order          SMALLINT    NOT NULL DEFAULT 1,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_species_company ON clinic.species (company_id, is_active);
CREATE TRIGGER trg_species_upd BEFORE UPDATE ON clinic.species
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.species IS
'Catálogo de especies: perro, gato, ave, reptil, humano. Base para la tabla breeds y el historial clínico.';

-- ============================================================
-- 2. BREEDS — Catálogo de razas por especie
-- ============================================================
CREATE TABLE clinic.breeds (
    id                  BIGSERIAL   PRIMARY KEY,
    species_id          BIGINT      NOT NULL REFERENCES clinic.species(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(150) NOT NULL,
    -- Ej: "Golden Retriever", "Siamés", "Bulldog Francés", "Periquito"

    size_category       VARCHAR(10),
    -- toy / small / medium / large / giant (para perros principalmente)

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_breed_species ON clinic.breeds (species_id, is_active);
CREATE TRIGGER trg_breed_upd BEFORE UPDATE ON clinic.breeds
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.breeds IS
'Razas por especie. Ej: Golden Retriever (perro), Siamés (gato), Yorkshire (perro).';

-- ============================================================
-- 3. PATIENTS — Paciente clínico (humano o animal)
--    Un registro unificado que sirve para clínica y veterinaria.
-- ============================================================
CREATE TABLE clinic.patients (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- ¿Paciente humano o animal?
    patient_type        VARCHAR(10)  NOT NULL DEFAULT 'human',
    -- human / animal

    -- Número de historia clínica (generado internamente)
    medical_record_number VARCHAR(50) NOT NULL,
    -- Ej: "HC-00001", "VET-2026-0042"

    -- ──────────────────────────────────────────
    -- CAMPOS PARA PACIENTE HUMANO
    -- ──────────────────────────────────────────

    -- Vinculo con hr.persons (si ya está registrado en el sistema)
    person_id           BIGINT      REFERENCES hr.persons(id),

    -- Si no está en hr.persons, datos básicos aquí
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    full_name           VARCHAR(200) GENERATED ALWAYS AS (
        TRIM(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''))
    ) STORED,

    birth_date          DATE,
    gender              VARCHAR(10),
    -- male / female / other / unknown

    national_id         VARCHAR(30),
    -- DNI, pasaporte, CE

    phone               VARCHAR(30),
    email               VARCHAR(200),
    address             VARCHAR(300),

    blood_type          VARCHAR(5),
    -- A+ / A- / B+ / B- / AB+ / AB- / O+ / O- / unknown

    -- ──────────────────────────────────────────
    -- CAMPOS PARA PACIENTE ANIMAL (VETERINARIA)
    -- ──────────────────────────────────────────

    -- Nombre del animal
    animal_name         VARCHAR(100),
    -- Ej: "Luna", "Max", "Pelusa"

    species_id          BIGINT      REFERENCES clinic.species(id),
    breed_id            BIGINT      REFERENCES clinic.breeds(id),

    -- Color/pelaje
    coat_color          VARCHAR(100),
    -- Ej: "Marrón con manchas blancas"

    -- Peso actual (kg) — se actualiza en cada consulta
    weight_kg           NUMERIC(8,3),

    -- Microchip
    microchip_number    VARCHAR(50),

    -- Número de pasaporte veterinario (viajes internacionales)
    vet_passport_number VARCHAR(50),

    -- ¿Esterilizado/castrado?
    is_neutered         BOOLEAN,
    neutered_date       DATE,

    -- ──────────────────────────────────────────
    -- CAMPOS COMUNES
    -- ──────────────────────────────────────────

    -- ¿Paciente activo en el sistema?
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Notas generales (visibles al médico/veterinario al abrir la ficha)
    clinical_notes      TEXT,

    -- Foto del paciente (URL)
    photo_url           VARCHAR(500),

    -- Fecha de primer registro en este centro
    first_visit_date    DATE,

    -- ¿Paciente de alto riesgo / alerta?
    has_alert           BOOLEAN     NOT NULL DEFAULT FALSE,
    alert_message       VARCHAR(300),
    -- Ej: "AGRESIVO — manejar con precaución", "ALÉRGICO A PENICILINA"

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_medical_record ON clinic.patients (company_id, medical_record_number);
CREATE INDEX idx_patient_person   ON clinic.patients (person_id) WHERE person_id IS NOT NULL;
CREATE INDEX idx_patient_microchip ON clinic.patients (microchip_number) WHERE microchip_number IS NOT NULL;
CREATE INDEX idx_patient_company  ON clinic.patients (company_id, patient_type, is_active);
CREATE TRIGGER trg_patient_upd BEFORE UPDATE ON clinic.patients
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.patients IS
'Paciente clínico unificado: humano (clínica/hospital) o animal (veterinaria). Discriminado por patient_type. Historia clínica N° única por empresa.';

-- ============================================================
-- 4. PATIENT_CONTACTS — Contactos de emergencia y dueños
--    Para humanos: contacto de emergencia, familiar, tutor
--    Para animales: dueño o responsable
-- ============================================================
CREATE TABLE clinic.patient_contacts (
    id                  BIGSERIAL   PRIMARY KEY,
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Tipo de vínculo
    contact_type        VARCHAR(30)  NOT NULL DEFAULT 'owner',
    -- owner           : dueño del animal (vet)
    -- emergency       : contacto de emergencia (humano)
    -- guardian        : tutor legal (menores)
    -- family          : familiar
    -- authorized      : persona autorizada a retirar al paciente

    -- Vinculo con cliente registrado (opcional)
    customer_id         BIGINT      REFERENCES sales.customers(id),

    -- Si no es un cliente registrado
    full_name           VARCHAR(200) NOT NULL,
    phone               VARCHAR(30),
    phone_alt           VARCHAR(30),
    email               VARCHAR(200),
    relationship        VARCHAR(50),
    -- Ej: "Madre", "Esposo/a", "Dueño", "Vecino autorizado"

    national_id         VARCHAR(30),
    address             VARCHAR(300),

    -- ¿Es el contacto principal?
    is_primary          BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Autorizado para tomar decisiones médicas?
    can_authorize_treatment BOOLEAN NOT NULL DEFAULT FALSE,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_pcontact_patient ON clinic.patient_contacts (patient_id, is_primary);
CREATE INDEX idx_pcontact_customer ON clinic.patient_contacts (customer_id) WHERE customer_id IS NOT NULL;
CREATE TRIGGER trg_pcontact_upd BEFORE UPDATE ON clinic.patient_contacts
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.patient_contacts IS
'Contactos del paciente: dueño (veterinaria), familiar/emergencia (clínica humana), tutor legal, persona autorizada para retiro.';

-- ============================================================
-- 5. PATIENT_BACKGROUND — Antecedentes médicos del paciente
--    Condiciones crónicas, cirugías previas, antecedentes
--    familiares. Un registro por condición/evento.
-- ============================================================
CREATE TABLE clinic.patient_background (
    id                  BIGSERIAL   PRIMARY KEY,
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Tipo de antecedente
    background_type     VARCHAR(30)  NOT NULL DEFAULT 'condition',
    -- condition       : enfermedad crónica (diabetes, hipertensión, epilepsia)
    -- surgery         : cirugía previa
    -- hospitalization : hospitalización previa
    -- family          : antecedente familiar (hereditario)
    -- habit           : hábito (tabaquismo, alcohol, sedentarismo)
    -- obstetric       : antecedentes obstétricos (partos, abortos)
    -- vaccination     : vacuna registrada manualmente (historial previo)

    -- Descripción
    description         VARCHAR(500) NOT NULL,
    -- Ej: "Diabetes Mellitus tipo 2 diagnosticada en 2018"
    --     "Apendicectomía — Hospital Nacional 2015"
    --     "Epilepsia controlada con Fenobarbital"

    -- Código diagnóstico (ICD-10 para humanos, libre para vet)
    icd10_code          VARCHAR(10),
    -- Ej: "E11", "K35.2", "G40"

    -- Fechas (aproximadas, puede ser solo el año)
    onset_date          DATE,
    -- Fecha de inicio/diagnóstico
    resolved_date       DATE,
    -- NULL si es crónico/activo

    -- ¿Sigue activo?
    is_active_condition BOOLEAN     NOT NULL DEFAULT TRUE,

    -- ¿Fue en este centro o en otro?
    source              VARCHAR(20)  NOT NULL DEFAULT 'self_reported',
    -- self_reported   : reportado por el paciente/dueño
    -- this_clinic     : diagnosticado/tratado aquí
    -- external        : registrado de documentos de otro centro

    -- Institución externa (si aplica)
    source_institution  VARCHAR(200),

    -- Observaciones del médico
    notes               TEXT,

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_background_patient ON clinic.patient_background (patient_id, background_type);
CREATE TRIGGER trg_background_upd BEFORE UPDATE ON clinic.patient_background
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.patient_background IS
'Antecedentes médicos: enfermedades crónicas, cirugías previas, hospitalizaciones, antecedentes familiares. Cada condición es un registro independiente.';

-- ============================================================
-- 6. PATIENT_ALLERGIES — Alergias conocidas
--    INMUTABLE: cada alergia registrada queda como evidencia.
--    Si se "resuelve", se marca resolved_at pero no se borra.
-- ============================================================
CREATE TABLE clinic.patient_allergies (
    id                  BIGSERIAL   PRIMARY KEY,
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Tipo de alérgeno
    allergen_type       VARCHAR(30)  NOT NULL DEFAULT 'medication',
    -- medication  : medicamento (penicilina, AINEs, contraste)
    -- food        : alimento (mariscos, nueces, lácteos)
    -- environmental: ambiental (pollen, polvo, latex)
    -- material    : material (latex, níquel, vendajes)
    -- anesthesia  : anestésico específico
    -- other       : otro

    -- Nombre del alérgeno
    allergen_name       VARCHAR(200) NOT NULL,
    -- Ej: "Penicilina", "Mariscos", "Látex", "Ibuprofeno"

    -- Reacción observada
    reaction            VARCHAR(300),
    -- Ej: "Shock anafiláctico", "Urticaria generalizada", "Vómitos"

    -- Severidad
    severity            VARCHAR(15)  NOT NULL DEFAULT 'moderate',
    -- mild / moderate / severe / life_threatening

    -- ¿Confirmada por prueba o solo referida?
    is_confirmed        BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Fuente del reporte?
    reported_by         VARCHAR(30)  NOT NULL DEFAULT 'patient',
    -- patient / guardian / physician / test

    -- Si fue detectada en una consulta nuestra
    consultation_id     BIGINT,
    -- REFERENCES clinic.consultations(id) — se agrega en 02_consultations.sql

    -- Fecha de primer episodio conocido
    first_episode_date  DATE,

    resolved_at         TIMESTAMPTZ,
    -- NULL = activa. Si se documenta resolución, se registra aquí.

    notes               TEXT,

    registered_by       BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE (no updated_at)
);
CREATE INDEX idx_allergy_patient  ON clinic.patient_allergies (patient_id);
CREATE INDEX idx_allergy_severity ON clinic.patient_allergies (severity)
    WHERE resolved_at IS NULL;
COMMENT ON TABLE clinic.patient_allergies IS
'Alergias conocidas del paciente. INMUTABLE — cada alergia es un registro permanente. Se marca resuelta (resolved_at) pero nunca se borra. Activa la alerta roja al prescribir.';

-- ============================================================
-- 7. PATIENT_INSURANCE — Seguro médico
--    Para clínicas humanas que trabajan con aseguradoras.
-- ============================================================
CREATE TABLE clinic.patient_insurance (
    id                  BIGSERIAL   PRIMARY KEY,
    patient_id          BIGINT      NOT NULL REFERENCES clinic.patients(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Aseguradora
    insurer_name        VARCHAR(200) NOT NULL,
    -- Ej: "RÍMAC", "Pacífico Seguros", "SIS", "EsSalud", "La Positiva"

    insurance_type      VARCHAR(20)  NOT NULL DEFAULT 'private',
    -- private     : seguro privado
    -- public      : seguro público (SIS, EsSalud)
    -- oncosalud   : plan oncológico

    -- Número de póliza / afiliado
    policy_number       VARCHAR(100) NOT NULL,
    affiliate_number    VARCHAR(100),

    -- Plan / cobertura
    plan_name           VARCHAR(200),
    -- Ej: "Plan Familia Premium", "SIS Subsidiado", "EsSalud T-1"

    -- Cobertura (%)
    coverage_pct        NUMERIC(5,2),
    -- Ej: 80.00 = 80% cubierto

    -- Deducible anual
    annual_deductible   NUMERIC(18,4),
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- Vigencia
    valid_from          DATE        NOT NULL,
    valid_until         DATE,

    -- ¿Seguro principal o secundario?
    is_primary          BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Datos de contacto de la aseguradora
    insurer_phone       VARCHAR(30),
    insurer_auth_code   VARCHAR(50),
    -- Código de autorización de procedimientos

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_insurance_patient ON clinic.patient_insurance (patient_id, is_primary);
CREATE TRIGGER trg_insurance_upd BEFORE UPDATE ON clinic.patient_insurance
    FOR EACH ROW EXECUTE FUNCTION clinic.set_updated_at();
COMMENT ON TABLE clinic.patient_insurance IS
'Cobertura de seguro médico del paciente: RÍMAC, EsSalud, SIS, etc. Soporta múltiples pólizas (principal + secundario).';
