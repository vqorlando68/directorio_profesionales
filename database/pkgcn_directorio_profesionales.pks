CREATE OR REPLACE PACKAGE pkgcn_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgcn_directorio_profesionales
    || Propósito: Capa Multi-Tabla de Casos de Negocio para el Directorio de
    ||            Profesionales de Salud y Cálculo de Disponibilidad Horaria.
    || Estándar: oracle-plsql-architecture
    || Responsabilidades:
    ||   - Búsqueda relacional de profesionales habilitados (rol 4, estado 1,
    ||     con franjas horarias registradas).
    ||   - Filtros combinados por especialidad, convenio, aseguramiento,
    ||     modalidad (Virtual/Domiciliaria) y búsqueda de texto con paginación.
    ||   - Motor de cálculo de disponibilidad y generación de slots con orden
    ||     estricto de prioridades (Horario por Día > Personalizado > Base).
    ||   - CERO COMMIT / ROLLBACK (gobernado por pkgln_directorio_profesionales).
    || =========================================================================
    */

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros
    PROCEDURE p_consultar_profesionales_json (
        p_id_especialidad       IN  NUMBER   DEFAULT NULL,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT NULL,
        p_modalidad             IN  VARCHAR2 DEFAULT NULL,
        p_busqueda              IN  VARCHAR2 DEFAULT NULL,
        p_pagina                IN  NUMBER   DEFAULT 1,
        p_registros_por_pagina  IN  NUMBER   DEFAULT 12,
        p_json_salida           OUT CLOB
    );

    -- 2. Consultar slots y vector de disponibilidad para un profesional y fecha específica
    PROCEDURE p_consultar_slots_dia_json (
        p_id_usuario            IN  NUMBER,
        p_fecha                 IN  DATE,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT 1,
        p_modalidad             IN  VARCHAR2 DEFAULT 'V',
        p_json_salida           OUT CLOB
    );

    -- 3. Consultar disponibilidad semanal de un profesional (7 días consecutivos)
    PROCEDURE p_consultar_slots_semana_json (
        p_id_usuario            IN  NUMBER,
        p_fecha_inicio          IN  DATE,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT 1,
        p_modalidad             IN  VARCHAR2 DEFAULT 'V',
        p_json_salida           OUT CLOB
    );

    -- 4. Consultar catálogos para filtros del directorio (especialidades, convenios, aseguramientos)
    PROCEDURE p_consultar_filtros_catalogo_json (
        p_json_salida OUT CLOB
    );

    -- 5. Consultar únicamente los intervalos disponibles de un día en formato 12h AM/PM
    -- Retorna: [{"INTERVALO":"08:20 PM"},{"INTERVALO":"08:40 PM"},...]
    PROCEDURE p_consultar_intervalos_dia_json (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 6. Consultar intervalos disponibles en un rango de fechas con formato dd/mm/yyyy
    -- Retorna: [{"fecha":"27/10/2026","intervalos":[{"INTERVALO":"08:20 PM"},...]},...]
    PROCEDURE p_consultar_intervalos_rango_json (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

END pkgcn_directorio_profesionales;
/

