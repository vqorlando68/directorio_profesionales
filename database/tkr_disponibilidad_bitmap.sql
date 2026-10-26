-- =============================================================================
-- PROYECTO: directorio-profesionales
-- ARTEFACTO: Script DDL para Creación de Tabla TKR_DISPONIBILIDAD_BITMAP
-- ESTÁNDAR: oracle-plsql-architecture
-- PROPÓSITO: Vector de bitmap (288 posiciones de 5 min) para búsquedas
--            ultrarrápidas de disponibilidad entre miles de profesionales.
-- =============================================================================

CREATE TABLE tkr_disponibilidad_bitmap (
    id                      NUMBER(12)          NOT NULL,
    id_usuario              NUMBER(12)          NOT NULL,
    fecha                   DATE                NOT NULL,
    id_convenio             NUMBER(12),
    id_tipo_aseguramiento   NUMBER(12)          DEFAULT 1 NOT NULL,
    modalidad               VARCHAR2(1)         DEFAULT 'V' NOT NULL,
    bitmap_disponible       VARCHAR2(288)       DEFAULT RPAD('0', 288, '0') NOT NULL,
    bitmap_ocupado          VARCHAR2(288)       DEFAULT RPAD('0', 288, '0') NOT NULL,
    slots_disponibles       NUMBER(4)           DEFAULT 0 NOT NULL,
    fecha_actualizacion     DATE                DEFAULT (SYSTIMESTAMP AT TIME ZONE 'America/Bogota') NOT NULL,
    CONSTRAINT tkr_disp_bitmap_pk PRIMARY KEY (id),
    CONSTRAINT tkr_disp_bitmap_usu_fk FOREIGN KEY (id_usuario)
        REFERENCES tkr_usuarios (id),
    CONSTRAINT tkr_disp_bitmap_conv_fk FOREIGN KEY (id_convenio)
        REFERENCES tkr_convenios (id),
    CONSTRAINT tkr_disp_bitmap_aseg_fk FOREIGN KEY (id_tipo_aseguramiento)
        REFERENCES tkr_tipos_aseguramiento (id),
    CONSTRAINT tkr_disp_bitmap_mod_ck CHECK (modalidad IN ('V', 'D')),
    CONSTRAINT tkr_disp_bitmap_uk UNIQUE (id_usuario, fecha, id_convenio, id_tipo_aseguramiento, modalidad)
);

COMMENT ON TABLE tkr_disponibilidad_bitmap IS 'Vector de disponibilidad horaria por bloques de 5 minutos (288 posiciones por día)';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.id IS 'Identificador único del registro de bitmap';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.id_usuario IS 'Identificador del profesional';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.fecha IS 'Fecha del día representado (YYYY-MM-DD)';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.id_convenio IS 'Convenio asociado (NULL si aplica de manera general)';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.id_tipo_aseguramiento IS 'Tipo de aseguramiento (1 = Voluntario, 2 = Obligatorio)';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.modalidad IS 'Modalidad de atención: V = Virtual, D = Domiciliaria';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.bitmap_disponible IS 'Cadena de 288 caracteres binarios (1 = Disponible, 0 = Inactivo)';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.bitmap_ocupado IS 'Cadena de 288 caracteres binarios (1 = Cita reservada/ocupada, 0 = Libre)';
COMMENT ON COLUMN tkr_disponibilidad_bitmap.slots_disponibles IS 'Cantidad total de slots disponibles en el día';

-- Índices para optimización de búsquedas masivas
CREATE INDEX tkr_disp_bitmap_busq_idx ON tkr_disponibilidad_bitmap (fecha, id_tipo_aseguramiento, modalidad, id_convenio);
CREATE INDEX tkr_disp_bitmap_usu_fec_idx ON tkr_disponibilidad_bitmap (id_usuario, fecha);

CREATE SEQUENCE tkr_disponibilidad_bitmap_seq
    START WITH 1
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

CREATE OR REPLACE TRIGGER trg_bi_tkr_disp_bitmap
    BEFORE INSERT
    ON tkr_disponibilidad_bitmap
    FOR EACH ROW
    WHEN (new.id IS NULL)
BEGIN
    :new.id := tkr_disponibilidad_bitmap_seq.NEXTVAL;
END;
/
