-- ============================================================
-- mantrasdb | Módulo Finance
-- Archivo: 01_accounts_periods.sql
-- Descripción: Plan de Cuentas, Ejercicios y Períodos contables.
--
-- Planes pre-cargados:
--   🇵🇪 PCGE Perú — Plan Contable General Empresarial (SUNAT)
--   🇪🇸 PGC España — Plan General Contable 2007
--
-- Diseño:
--   accounts con company_id = NULL son PLANTILLAS del sistema.
--   Cuando se configura una empresa, se copian a accounts con
--   su company_id. Esto permite personalizar el plan sin romper
--   la plantilla.
--
--   Doble partida: SUM(debits) = SUM(credits) siempre.
--   Los asientos viven en 02_journal_entries.sql.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS finance;

-- Función de timestamp automático (igual que en sales y logistics)
CREATE OR REPLACE FUNCTION finance.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ============================================================
-- 1. TIPOS DE CUENTA
--    Clasificación fundamental para el balance y el P&L.
-- ============================================================
CREATE TABLE finance.account_types (
    id              SERIAL      PRIMARY KEY,
    code            VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(100) NOT NULL,
    name_es         VARCHAR(100) NOT NULL,

    -- ¿Qué estado financiero la contiene?
    financial_statement VARCHAR(20) NOT NULL,
    -- balance_sheet   : Balance General / Estado de Situación
    -- income_statement: Estado de Resultados / P&L
    -- cost_account    : Cuentas de costos (90-99 PCGE)
    -- memo_account    : Cuentas de orden (memorando)

    -- Saldo normal de las cuentas de este tipo
    normal_balance  VARCHAR(10) NOT NULL,
    -- debit  : activos, costos, gastos (aumentan con débito)
    -- credit : pasivos, patrimonio, ingresos (aumentan con crédito)

    -- ¿Aumenta o disminuye el patrimonio?
    increases_equity BOOLEAN NOT NULL DEFAULT FALSE,

    sort_order      INTEGER NOT NULL DEFAULT 0
);

INSERT INTO finance.account_types (code, name, name_es, financial_statement, normal_balance, increases_equity, sort_order) VALUES
('ASSET_CURRENT',   'Current Assets',         'Activo Corriente',             'balance_sheet',    'debit',  FALSE, 10),
('ASSET_NONCURRENT','Non-Current Assets',      'Activo No Corriente',          'balance_sheet',    'debit',  FALSE, 20),
('LIABILITY_CURRENT','Current Liabilities',    'Pasivo Corriente',             'balance_sheet',    'credit', FALSE, 30),
('LIABILITY_LONG',  'Non-Current Liabilities', 'Pasivo No Corriente',          'balance_sheet',    'credit', FALSE, 40),
('EQUITY',          'Equity',                  'Patrimonio Neto',              'balance_sheet',    'credit', TRUE,  50),
('REVENUE',         'Revenue',                 'Ingresos',                     'income_statement', 'credit', TRUE,  60),
('COST',            'Cost of Goods Sold',      'Costo de Ventas',              'income_statement', 'debit',  FALSE, 70),
('EXPENSE',         'Expenses',                'Gastos',                       'income_statement', 'debit',  FALSE, 80),
('COST_ACCOUNT',    'Cost Accounting',         'Contabilidad de Costos',       'cost_account',     'debit',  FALSE, 90),
('MEMO',            'Memo / Order Accounts',   'Cuentas de Orden',             'memo_account',     'debit',  FALSE, 99);

COMMENT ON TABLE finance.account_types IS 'Clasificación de cuentas para estados financieros. normal_balance indica si aumentan con Débito o Crédito.';

-- ============================================================
-- 2. PLAN DE CUENTAS (CHART OF ACCOUNTS)
--    Estructura jerárquica: Elemento → Cuenta → Subcuenta → Detalle
--    company_id = NULL → plantilla del sistema (PCGE / PGC)
--    company_id = ID   → cuenta específica de la empresa
-- ============================================================
CREATE TABLE finance.accounts (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      REFERENCES hr.companies(id) ON DELETE RESTRICT,
    -- NULL = plantilla del sistema

    parent_id           BIGINT      REFERENCES finance.accounts(id),
    -- NULL = cuenta raíz del elemento

    account_type_id     INTEGER     NOT NULL REFERENCES finance.account_types(id),

    -- País del plan contable
    country_code        VARCHAR(5)  NOT NULL DEFAULT 'PE',
    -- PE=Perú (PCGE) | ES=España (PGC) | CO=Colombia | MX=México

    -- Código y nombre
    code                VARCHAR(20) NOT NULL,
    -- Perú: "10", "101", "1011", "10111"
    -- España: "1", "10", "100", "1000"
    name                VARCHAR(300) NOT NULL,
    description         TEXT,

    -- Nivel en la jerarquía
    level               SMALLINT    NOT NULL DEFAULT 1,
    -- 1 = elemento (1 dígito: Perú) / grupo (1 dígito: España)
    -- 2 = cuenta (2 dígitos: Perú) / subgrupo (2 dígitos: España)
    -- 3 = subcuenta (3-4 dígitos)
    -- 4 = análisis (4-6 dígitos)

    -- ¿Puede recibir líneas de asiento?
    is_posting          BOOLEAN     NOT NULL DEFAULT FALSE,
    -- FALSE = solo agrupadora (no puede usarse en asientos)
    -- TRUE  = cuenta hoja (se usa en journal_entry_lines)

    -- Saldo normal (heredado del tipo, pero se puede sobrescribir)
    normal_balance      VARCHAR(10) NOT NULL DEFAULT 'debit',
    -- debit | credit

    -- Moneda (NULL = moneda base de la empresa)
    currency            VARCHAR(10),

    -- Para cuentas de impuesto (enlace con sales.tax_rates)
    tax_rate_id         INTEGER     REFERENCES sales.tax_rates(id),

    -- Código SUNAT (para Libros Electrónicos PLE)
    sunat_account_code  VARCHAR(20),
    -- código del catálogo SUNAT para el PLE

    -- Código PGC (España)
    pgc_code            VARCHAR(20),

    -- ¿Requiere análisis por tercero? (clientes, proveedores)
    requires_partner    BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = al usar esta cuenta en un asiento se debe indicar
    --        customer_id o supplier_id para la cuenta corriente

    -- ¿Requiere análisis por centro de costo?
    requires_cost_center BOOLEAN   NOT NULL DEFAULT FALSE,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    is_template         BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE si es plantilla del sistema (company_id = NULL)

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, country_code, code)
);

CREATE INDEX idx_accounts_company     ON finance.accounts (company_id);
CREATE INDEX idx_accounts_parent      ON finance.accounts (parent_id);
CREATE INDEX idx_accounts_code        ON finance.accounts (country_code, code);
CREATE INDEX idx_accounts_type        ON finance.accounts (account_type_id);
CREATE INDEX idx_accounts_posting     ON finance.accounts (is_posting) WHERE is_posting = TRUE;

CREATE TRIGGER trg_accounts_updated_at
    BEFORE UPDATE ON finance.accounts
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.accounts              IS 'Plan de Cuentas jerárquico. company_id=NULL → plantillas PCGE/PGC. is_posting=TRUE → cuenta hoja usable en asientos.';
COMMENT ON COLUMN finance.accounts.is_posting   IS 'TRUE = cuenta de detalle, usable en journal_entry_lines. FALSE = solo agrupadora para reportes.';
COMMENT ON COLUMN finance.accounts.requires_partner IS 'TRUE = al usar en asiento se debe indicar cliente o proveedor (ej: cuentas 12x, 42x).';

-- ============================================================
-- 🇵🇪 PLAN CONTABLE GENERAL EMPRESARIAL (PCGE) — PERÚ
--    Resolución CONASEV. Pre-cargado como plantilla.
--    Estructura: Elemento (1d) → Cuenta (2d) → Divisionaria (3-4d)
-- ============================================================

-- ELEMENTO 1: ACTIVOS DISPONIBLES Y EXIGIBLES (10-19)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '1',    'ACTIVOS CORRIENTES', 1, FALSE, 'debit', TRUE),
-- 10: Efectivo y equivalentes
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '10',   'Efectivo y Equivalentes de Efectivo', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '101',  'Caja', 3, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '1011', 'Caja', 4, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '102',  'Fondos Fijos (Caja Chica)', 3, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '1021', 'Fondo fijo', 4, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '104',  'Cuentas Corrientes en Instituciones Financieras', 3, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '1041', 'Cuentas corrientes operativas', 4, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '1042', 'Cuentas corrientes en moneda extranjera', 4, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '106',  'Depósitos en Tránsito', 3, TRUE, 'debit', TRUE),
-- 12: Cuentas por cobrar comerciales
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '12',   'Cuentas por Cobrar Comerciales – Terceros', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '121',  'Facturas, Boletas y Otros Comprobantes por Cobrar', 3, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '1211', 'No emitidas', 4, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '1212', 'Emitidas en cartera', 4, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '122',  'Anticipos de Clientes', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '123',  'Letras por Cobrar', 3, TRUE, 'debit', TRUE),
-- 13: Cuentas por cobrar comerciales relacionadas
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '13',   'Cuentas por Cobrar Comerciales – Relacionadas', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '131',  'Facturas, Boletas por Cobrar Relacionadas', 3, TRUE, 'debit', TRUE),
-- 16: Cuentas por cobrar diversas
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '16',   'Cuentas por Cobrar Diversas – Terceros', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '161',  'Préstamos', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '165',  'Depósitos en Garantía', 3, TRUE, 'debit', TRUE),
-- 17: Cuentas por cobrar a personal
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '17',   'Cuentas por Cobrar a Accionistas, Directores y Gerentes', 2, TRUE, 'debit', TRUE),
-- 18: Servicios y otros contratados por anticipado
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '18',   'Servicios y Otros Contratados por Anticipado', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '181',  'Costos Financieros por Devengar', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '182',  'Seguros por Devengar', 3, TRUE, 'debit', TRUE),
-- 19: Estimación de cuentas de cobranza dudosa
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '19',   'Estimación de Cuentas de Cobranza Dudosa', 2, TRUE, 'credit', TRUE);

-- ELEMENTO 2: ACTIVOS REALIZABLES (Inventarios 20-29)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '2',    'INVENTARIOS', 1, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '20',   'Mercaderías', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '201',  'Mercaderías Manufacturadas', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '21',   'Productos Terminados', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '22',   'Subproductos, Desechos y Desperdicios', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '23',   'Productos en Proceso', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '24',   'Materias Primas', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '25',   'Materiales Auxiliares, Suministros y Repuestos', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '251',  'Materiales Auxiliares', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '252',  'Suministros', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '253',  'Repuestos', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '26',   'Envases y Embalajes', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '28',   'Existencias por Recibir', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'), 'PE', '29',   'Desvalorización de Existencias', 2, TRUE, 'credit', TRUE);

-- ELEMENTO 3: ACTIVOS NO CORRIENTES (30-39)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '3',    'ACTIVOS NO CORRIENTES', 1, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '30',   'Inversiones Mobiliarias', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '31',   'Propiedades de Inversión', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '32',   'Activos Adquiridos en Arrendamiento Financiero', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '33',   'Inmuebles, Maquinaria y Equipo', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '331',  'Terrenos', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '332',  'Edificios y Otras Construcciones', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '333',  'Maquinarias y Equipos de Explotación', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '334',  'Unidades de Transporte', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '335',  'Muebles y Enseres', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '336',  'Equipos Diversos', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '337',  'Herramientas y Unidades de Reemplazo', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '338',  'Unidades por Recibir', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '34',   'Activos Intangibles', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '341',  'Concesiones, Licencias y Otros Derechos', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '343',  'Programas de Computadora (Software)', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '344',  'Costos de Exploración, Evaluación y Desarrollo', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '37',   'Activo Diferido', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '371',  'Impuesto a la Renta Diferido – Activo', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '39',   'Depreciación, Amortización y Agotamiento Acumulados', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '391',  'Depreciación Acumulada', 3, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '3913', 'Inmuebles, Maquinaria y Equipo', 4, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'PE', '392',  'Amortización Acumulada', 3, TRUE, 'credit', TRUE);

-- ELEMENTO 4: PASIVOS (40-49)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, requires_partner, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '4',    'PASIVOS', 1, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '40',   'Tributos, Contraprestaciones y Aportes al Sistema Público', 2, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '401',  'Gobierno Central', 3, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '4011', 'Impuesto General a las Ventas (IGV)', 4, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '4012', 'IGV – Régimen de Retenciones', 4, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '4013', 'IGV – Régimen de Percepciones', 4, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '4017', 'Impuesto a la Renta', 4, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '4018', 'Detracciones (SPOT)', 4, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '403',  'Instituciones Públicas', 3, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '4031', 'EsSalud', 4, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '4032', 'ONP', 4, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '41',   'Remuneraciones y Participaciones por Pagar', 2, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '411',  'Remuneraciones por Pagar', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '413',  'Participaciones por Pagar', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '415',  'Beneficios Sociales de los Trabajadores por Pagar', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '419',  'Otras Remuneraciones y Participaciones por Pagar', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '42',   'Cuentas por Pagar Comerciales – Terceros', 2, FALSE, 'credit', TRUE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '421',  'Facturas, Boletas y Otros Comprobantes por Pagar', 3, TRUE, 'credit', TRUE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '422',  'Anticipos a Proveedores', 3, TRUE, 'debit', TRUE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '423',  'Letras por Pagar', 3, TRUE, 'credit', TRUE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '43',   'Cuentas por Pagar Comerciales – Relacionadas', 2, TRUE, 'credit', TRUE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '44',   'Cuentas por Pagar a Accionistas, Directores y Gerentes', 2, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '45',   'Obligaciones Financieras', 2, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '451',  'Préstamos de Instituciones Financieras', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '452',  'Contratos de Arrendamiento Financiero', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '46',   'Cuentas por Pagar Diversas – Terceros', 2, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '461',  'Reclamaciones de Terceros', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '469',  'Otras Cuentas por Pagar Diversas', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '47',   'Pasivo Diferido', 2, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '471',  'Impuesto a la Renta Diferido – Pasivo', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '49',   'Pasivo Estimado', 2, FALSE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '491',  'Beneficios Sociales de los Trabajadores', 3, TRUE, 'credit', FALSE, TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'), 'PE', '499',  'Otros Pasivos Estimados', 3, TRUE, 'credit', FALSE, TRUE);

-- ELEMENTO 5: PATRIMONIO NETO (50-59)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '5',    'PATRIMONIO NETO', 1, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '50',   'Capital', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '501',  'Capital Social', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '52',   'Capital Adicional', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '56',   'Resultados No Realizados', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '57',   'Excedente de Revaluación', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '58',   'Reservas', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '581',  'Reserva Legal', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '589',  'Otras Reservas', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '59',   'Resultados Acumulados', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '591',  'Utilidades No Distribuidas', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'), 'PE', '592',  'Pérdidas Acumuladas', 3, TRUE, 'debit', TRUE);

-- ELEMENTO 6: GASTOS POR NATURALEZA (60-69)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '6',    'GASTOS POR NATURALEZA', 1, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '60',   'Compras', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '601',  'Mercaderías', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '602',  'Materias Primas', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '603',  'Materiales Auxiliares, Suministros y Repuestos', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '606',  'Suministros', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '61',   'Variación de Inventarios', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '611',  'Mercaderías', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '612',  'Materias Primas', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '62',   'Gastos de Personal, Directores y Gerentes', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '621',  'Remuneraciones', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '622',  'Otras Remuneraciones', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '623',  'Indemnizaciones al Personal', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '625',  'Atención al Personal', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '627',  'Seguridad y Previsión Social (EsSalud, ONP)', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '628',  'Compensación por Tiempo de Servicios (CTS)', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '63',   'Gastos de Servicios Prestados por Terceros', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '631',  'Transporte, Correos y Gastos de Viaje', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '632',  'Asesoría y Consultoría', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '634',  'Mantenimiento y Reparaciones', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '635',  'Alquileres', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '636',  'Servicios Básicos (Agua, Luz, Internet)', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '637',  'Publicidad, Publicaciones y Relaciones Públicas', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '639',  'Otros Servicios de Terceros', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '64',   'Gastos por Tributos', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '641',  'Gobierno Central (Impuesto a la Renta)', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '642',  'Gobierno Local (Impuesto Predial, Alcabala)', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '65',   'Otros Gastos de Gestión', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '651',  'Seguros', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '655',  'Costo Neto de Enajenación de Activos', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '659',  'Otros Gastos de Gestión', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '67',   'Gastos Financieros', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '671',  'Gastos en Operaciones de Endeudamiento', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '673',  'Pérdida por Diferencia de Cambio', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '675',  'Descuentos Concedidos', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '68',   'Valuación y Deterioro de Activos y Provisiones', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '681',  'Depreciación', 3, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '6813', 'Depreciación – Inmuebles, Maquinaria y Equipo', 4, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '682',  'Amortización de Intangibles', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'), 'PE', '686',  'Provisión para Cuentas de Cobranza Dudosa', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '69',   'Costo de Ventas', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '691',  'Costo de Ventas – Mercaderías', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '692',  'Costo de Ventas – Productos Terminados', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),    'PE', '699',  'Costo de Ventas – Otros', 3, TRUE, 'debit', TRUE);

-- ELEMENTO 7: INGRESOS (70-79)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '7',    'INGRESOS', 1, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '70',   'Ventas', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '701',  'Mercaderías', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '702',  'Productos Terminados', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '706',  'Prestación de Servicios', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '708',  'Otros Ingresos Operacionales', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '709',  'Devoluciones sobre Ventas', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '71',   'Variación de la Producción Almacenada', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '75',   'Otros Ingresos de Gestión', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '751',  'Ingresos por Comisiones', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '752',  'Ingresos por Alquileres', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '759',  'Otros Ingresos de Gestión', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '77',   'Ingresos Financieros', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '771',  'Ganancia por Instrumentos Financieros', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '773',  'Ganancia por Diferencia de Cambio', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '775',  'Descuentos Obtenidos', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '778',  'Intereses y Rendimientos', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '78',   'Cargas Cubiertas por Provisiones', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '79',   'Cargas Imputables a Cuentas de Costos', 2, TRUE, 'credit', TRUE);

-- ELEMENTO 8: SALDO DE GESTIÓN (80-89)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '8',    'SALDO DE GESTIÓN', 1, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '80',   'Margen Comercial', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '81',   'Producción del Ejercicio', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '82',   'Valor Agregado', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '85',   'Resultado antes de Impuesto a la Renta', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '88',   'Impuesto a la Renta', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'), 'PE', '89',   'Resultado del Ejercicio', 2, TRUE, 'credit', TRUE);

-- ELEMENTO 9: CUENTAS DE COSTOS (90-99)
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '9',    'CONTABILIDAD DE COSTOS', 1, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '90',   'Costo de Producción', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '91',   'Costo de Producción – Materiales Directos', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '92',   'Costo de Producción – Mano de Obra Directa', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '93',   'Costo de Producción – Costos Indirectos', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '94',   'Gastos de Administración', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '95',   'Gastos de Ventas', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '96',   'Gastos Financieros', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '97',   'Gastos en Investigación y Desarrollo', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST_ACCOUNT'), 'PE', '99',   'Ganancia/Pérdida por Diferencia de Cambio', 2, TRUE, 'debit', TRUE);

-- ============================================================
-- 🇪🇸 PLAN GENERAL CONTABLE (PGC) — ESPAÑA 2007
--    Real Decreto 1514/2007. Grupos 1-9.
-- ============================================================
INSERT INTO finance.accounts (company_id, account_type_id, country_code, code, name, level, is_posting, normal_balance, is_template) VALUES
-- GRUPO 1: Financiación básica
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '1',   'FINANCIACIÓN BÁSICA', 1, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '10',  'Capital', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '100', 'Capital Social', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '11',  'Reservas y otros instrumentos de patrimonio', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '112', 'Reserva Legal', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '113', 'Reservas Voluntarias', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '12',  'Resultados pendientes de aplicación', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '120', 'Remanente', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '121', 'Resultados Negativos de Ejercicios Anteriores', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EQUITY'),           'ES', '129', 'Resultado del Ejercicio', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_LONG'),   'ES', '17',  'Deudas a largo plazo por préstamos recibidos', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_LONG'),   'ES', '170', 'Deudas a largo plazo con entidades de crédito', 3, TRUE, 'credit', TRUE),
-- GRUPO 2: Activo no corriente
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '2',   'ACTIVO NO CORRIENTE', 1, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '20',  'Inmovilizaciones intangibles', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '205', 'Aplicaciones Informáticas', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '21',  'Inmovilizaciones materiales', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '210', 'Terrenos y Bienes Naturales', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '211', 'Construcciones', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '213', 'Maquinaria', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '216', 'Mobiliario', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '217', 'Equipos para Procesos de Información', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '218', 'Elementos de Transporte', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '28',  'Amortización acumulada del inmovilizado', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '281', 'Amortización Acumulada Inmovilizado Intangible', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_NONCURRENT'), 'ES', '282', 'Amortización Acumulada Inmovilizado Material', 3, TRUE, 'credit', TRUE),
-- GRUPO 3: Existencias
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '3',   'EXISTENCIAS', 1, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '30',  'Comerciales', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '31',  'Materias Primas', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '32',  'Otros Aprovisionamientos', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '33',  'Productos en Curso', 2, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '35',  'Productos Terminados', 2, TRUE, 'debit', TRUE),
-- GRUPO 4: Acreedores y deudores por operaciones comerciales
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '4',   'ACREEDORES Y DEUDORES', 1, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '40',  'Proveedores', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '400', 'Proveedores', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '407', 'Anticipos a Proveedores', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '43',  'Clientes', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '430', 'Clientes', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '438', 'Anticipos de Clientes', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '47',  'Administraciones Públicas', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '470', 'Hacienda Pública Deudora por Retenciones', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '472', 'Hacienda Pública – IVA Soportado', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '477', 'Hacienda Pública – IVA Repercutido', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '4750','Hacienda Pública Acreedora por Impuesto Sociedades', 4, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='LIABILITY_CURRENT'),'ES', '476', 'Organismos de la Seguridad Social (SS)', 3, TRUE, 'credit', TRUE),
-- GRUPO 5: Cuentas financieras
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '5',   'CUENTAS FINANCIERAS', 1, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '52',  'Deudas a corto plazo', 2, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '57',  'Tesorería', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '570', 'Caja (euros)', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='ASSET_CURRENT'),    'ES', '572', 'Bancos e Instituciones de Crédito', 3, TRUE, 'debit', TRUE),
-- GRUPO 6: Compras y Gastos
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '6',   'COMPRAS Y GASTOS', 1, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),             'ES', '60',  'Compras', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),             'ES', '600', 'Compras de Mercaderías', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),             'ES', '601', 'Compras de Materias Primas', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '62',  'Servicios Exteriores', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '621', 'Arrendamientos y Cánones', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '622', 'Reparaciones y Conservación', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '623', 'Servicios de Profesionales Independientes', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '625', 'Primas de Seguros', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '628', 'Suministros (Agua, Gas, Electricidad)', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '64',  'Gastos de Personal', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '640', 'Sueldos y Salarios', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '642', 'Seguridad Social a Cargo de la Empresa', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '65',  'Otros Gastos de Gestión', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '66',  'Gastos Financieros', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '662', 'Intereses de Deudas', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '668', 'Diferencias Negativas de Cambio', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '68',  'Dotaciones para Amortizaciones', 2, FALSE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '681', 'Amortización del Inmovilizado Intangible', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='EXPENSE'),          'ES', '682', 'Amortización del Inmovilizado Material', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='COST'),             'ES', '69',  'Pérdidas por Deterioro y Otras', 2, TRUE, 'debit', TRUE),
-- GRUPO 7: Ventas e Ingresos
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '7',   'VENTAS E INGRESOS', 1, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '70',  'Ventas de Mercaderías, Productos y Servicios', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '700', 'Ventas de Mercaderías', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '705', 'Prestaciones de Servicios', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '706', 'Descuentos sobre Ventas por Pronto Pago', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '708', 'Devoluciones de Ventas y Operaciones Similares', 3, TRUE, 'debit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '75',  'Otros Ingresos de Gestión', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '752', 'Ingresos por Arrendamientos', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '76',  'Ingresos Financieros', 2, FALSE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '763', 'Beneficios por Diferencias de Cambio', 3, TRUE, 'credit', TRUE),
(NULL, (SELECT id FROM finance.account_types WHERE code='REVENUE'),          'ES', '769', 'Otros Ingresos Financieros', 3, TRUE, 'credit', TRUE);

-- ============================================================
-- 3. EJERCICIOS FISCALES (FISCAL YEARS)
-- ============================================================
CREATE TABLE finance.fiscal_years (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    code            VARCHAR(20) NOT NULL,
    -- "2026", "2025-2026" (para ejercicios no-calendarios)
    name            VARCHAR(100) NOT NULL,

    start_date      DATE        NOT NULL,
    end_date        DATE        NOT NULL,

    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open      : activo, se pueden registrar asientos
    -- closed    : ejercicio cerrado, solo lectura
    -- locked    : bloqueado después de auditoría

    -- Cierre del ejercicio
    closing_date    DATE,
    closing_entry_id BIGINT,
    -- REFERENCES finance.journal_entries(id) — FK diferida

    created_by      BIGINT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code),
    CHECK (end_date > start_date)
);

CREATE INDEX idx_fiscal_years_company ON finance.fiscal_years (company_id);

CREATE TRIGGER trg_fiscal_years_updated_at
    BEFORE UPDATE ON finance.fiscal_years
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE finance.fiscal_years IS 'Ejercicios fiscales. El cierre de ejercicio genera un asiento de regularización y bloquea el período.';

-- ============================================================
-- 4. PERÍODOS CONTABLES (ACCOUNTING PERIODS)
--    Meses dentro del ejercicio. Los asientos se asignan
--    a un período específico. Cada período tiene su estado.
-- ============================================================
CREATE TABLE finance.accounting_periods (
    id              BIGSERIAL   PRIMARY KEY,
    fiscal_year_id  BIGINT      NOT NULL REFERENCES finance.fiscal_years(id) ON DELETE RESTRICT,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    period_number   SMALLINT    NOT NULL,
    -- 1=enero, 2=febrero, ..., 12=diciembre, 13=ajustes, 14=cierre

    name            VARCHAR(50) NOT NULL,
    -- "Enero 2026", "Ajustes 2026"

    start_date      DATE        NOT NULL,
    end_date        DATE        NOT NULL,

    period_type     VARCHAR(20) NOT NULL DEFAULT 'regular',
    -- regular   : período mensual normal
    -- adjustment : período 13 para asientos de ajuste (provisiones, diferidos)
    -- closing    : período 14 para el asiento de cierre del ejercicio

    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open      : se pueden registrar y modificar asientos draft
    -- in_closing: en proceso de cierre (solo correcciones con aprobación)
    -- closed    : cerrado, no se pueden añadir más asientos
    -- locked    : bloqueado post-auditoría, inmutable

    -- Quién cerró el período
    closed_by       BIGINT,
    closed_at       TIMESTAMPTZ,

    -- Balance de apertura (calculado al cerrar el período anterior)
    opening_balance_calculated BOOLEAN NOT NULL DEFAULT FALSE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (fiscal_year_id, period_number),
    CHECK (end_date >= start_date)
);

CREATE INDEX idx_accounting_periods_year    ON finance.accounting_periods (fiscal_year_id);
CREATE INDEX idx_accounting_periods_company ON finance.accounting_periods (company_id);
CREATE INDEX idx_accounting_periods_dates   ON finance.accounting_periods (start_date, end_date);

CREATE TRIGGER trg_accounting_periods_updated_at
    BEFORE UPDATE ON finance.accounting_periods
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.accounting_periods          IS 'Períodos contables mensuales dentro del ejercicio fiscal. Los asientos se deben asociar a un período abierto.';
COMMENT ON COLUMN finance.accounting_periods.period_number IS '1-12 = meses normales. 13 = período de ajustes (provisiones, diferidos). 14 = asiento de cierre del ejercicio.';
COMMENT ON COLUMN finance.accounting_periods.status   IS 'open → in_closing → closed → locked. Un período cerrado no acepta nuevos asientos.';
