-- =============================================================================
-- PROYECTO: Directorio de Profesionales y Disponibilidad de Horarios
-- SCRIPT  : creacion_indices.sql
-- OBJETIVO: Índices compuestos recomendados para optimizar el tiempo de
--           respuesta en consultas de disponibilidad, jerarquías de horarios
--           y filtrado multidimensional de profesionales.
-- ESQUEMA : TEKER_DEV
-- =============================================================================

PROMPT Creando indices para optimizacion de disponibilidad y directorio...

-- 1. Evaluacion de turnos y jerarquias en tkr_horarios_profesional
-- Optimiza el filtrado por profesional, estado activo, dia de la semana y rango de fechas (Nivel 1, 2 y 3)
BEGIN
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tkr_horarios_disp ON TEKER_DEV.TKR_HORARIOS_PROFESIONAL (ID_USUARIO, ACTIVO, DIA_SEMANA, FECHA_INICIAL, FECHA_FINAL)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN NULL; ELSE RAISE; END IF;
END;
/

-- 2. Evaluacion de tipo de aseguramiento y convenios en tkr_horarios_profesional
-- Optimiza la regla de aseguramiento universal (NULL) y convenios especificos
BEGIN
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tkr_horarios_aseg_conv ON TEKER_DEV.TKR_HORARIOS_PROFESIONAL (ID_USUARIO, ID_TIPO_ASEGURAMIENTO, ID_CONVENIO, ACTIVO)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN NULL; ELSE RAISE; END IF;
END;
/

-- 3. Tabla de tiempos y duraciones de atencion en tkr_tiempos_atencion
-- Permite resolver al instante la duracion en minutos segun modalidad y tipo de aseguramiento
BEGIN
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tkr_tiempos_atencion_prof ON TEKER_DEV.TKR_TIEMPOS_ATENCION (ID_USUARIO, ID_TIPO_ASEGURAMIENTO, ACTIVO)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN NULL; ELSE RAISE; END IF;
END;
/

-- 4. Verificacion de ausencias programadas en tkr_ausencias_profesional
-- Optimiza el chequeo de bloqueos por vacaciones o ausencias en pkgca_tkr_ausencias_profesional
BEGIN
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tkr_ausencias_rango ON TEKER_DEV.TKR_AUSENCIAS_PROFESIONAL (ID_USUARIO, FECHA_INICIAL, FECHA_FINAL)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN NULL; ELSE RAISE; END IF;
END;
/

-- 5. Modalidades de atencion del profesional en tkr_franjas_profesional
-- Acelera el filtrado de profesionales habilitados por Telemedicina o Domiciliaria
BEGIN
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tkr_franjas_prof_mod ON TEKER_DEV.TKR_FRANJAS_PROFESIONAL (ID_USUARIO, ACTIVO, MODALIDAD)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN NULL; ELSE RAISE; END IF;
END;
/

-- 6. Especialidades asignadas al profesional en tkr_especialidades_usuario
-- Acelera la busqueda y filtrado por especialidad medica en el directorio
BEGIN
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tkr_espec_usr_esp ON TEKER_DEV.TKR_ESPECIALIDADES_USUARIO (ID_USUARIO, ID_ESPECIALIDAD)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN NULL; ELSE RAISE; END IF;
END;
/

PROMPT Indices creados exitosamente.
