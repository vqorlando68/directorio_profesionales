CREATE OR REPLACE PACKAGE PKGTKR_DISPONIBILIDAD_BITMAP_DAO
AS
    -- =============================================================================
    -- PAQUETE DAO: PKGTKR_DISPONIBILIDAD_BITMAP_DAO
    -- ESTÁNDAR: oracle-plsql-architecture (20 métodos oficiales)
    -- TABLA: tkr_disponibilidad_bitmap
    -- =============================================================================

    -- Tipo colección para consultas generales
    TYPE t_tkr_disponibilidad_bitmap IS TABLE OF tkr_disponibilidad_bitmap%ROWTYPE INDEX BY BINARY_INTEGER;

    -- 1. Insertar registro completo
    PROCEDURE p_insertar (
        pro_tkr_disponibilidad_bitmap IN tkr_disponibilidad_bitmap%ROWTYPE
    );

    -- 2. Traer registro por PK
    FUNCTION f_traer (
        pty_id IN tkr_disponibilidad_bitmap.id%TYPE
    ) RETURN tkr_disponibilidad_bitmap%ROWTYPE;

    -- 3. Consultar todos los registros
    PROCEDURE p_consultar_registros (
        pta_tkr_disponibilidad_bitmap OUT pkgtkr_disponibilidad_bitmap_dao.t_tkr_disponibilidad_bitmap
    );

    -- 4. Eliminar registro por ROWID
    PROCEDURE p_eliminar_rowid (
        p_rowid IN VARCHAR2
    );

    -- 5. Eliminar registro por PK
    PROCEDURE p_eliminar (
        pty_id IN tkr_disponibilidad_bitmap.id%TYPE
    );

    -- 6. Eliminar todos los registros (Uso restringido)
    PROCEDURE p_eliminar_registros;

    -- 7. Verificar existencia por PK
    FUNCTION f_existe (
        pty_id IN tkr_disponibilidad_bitmap.id%TYPE
    ) RETURN BOOLEAN;

    -- 8. Verificar existencia y retornar registro
    FUNCTION f_existe (
        pty_id                        IN  tkr_disponibilidad_bitmap.id%TYPE,
        pro_tkr_disponibilidad_bitmap OUT tkr_disponibilidad_bitmap%ROWTYPE
    ) RETURN BOOLEAN;

    -- 9. Verificar existencia, retornar registro y ROWID
    FUNCTION f_existe (
        pty_id                        IN  tkr_disponibilidad_bitmap.id%TYPE,
        pro_tkr_disponibilidad_bitmap OUT tkr_disponibilidad_bitmap%ROWTYPE,
        p_rowid                       OUT VARCHAR2
    ) RETURN BOOLEAN;

    -- 10. Verificar existencia por ROWID
    FUNCTION f_existe_rowid (
        p_rowid IN VARCHAR2
    ) RETURN BOOLEAN;

    -- 11. Verificar existencia por ROWID y retornar registro
    FUNCTION f_existe_rowid (
        p_rowid                       IN  VARCHAR2,
        pro_tkr_disponibilidad_bitmap OUT tkr_disponibilidad_bitmap%ROWTYPE
    ) RETURN BOOLEAN;

    -- 12. Actualizar registro completo por PK en ROWTYPE
    PROCEDURE p_actualizar (
        pro_tkr_disponibilidad_bitmap IN tkr_disponibilidad_bitmap%ROWTYPE
    );

    -- 13. Actualizar indicando PK explícita
    PROCEDURE p_actualizar (
        pro_tkr_disponibilidad_bitmap IN tkr_disponibilidad_bitmap%ROWTYPE,
        pty_id                        IN tkr_disponibilidad_bitmap.id%TYPE
    );

    -- 14. Actualizar por ROWID
    PROCEDURE p_actualizar_rowid (
        pro_tkr_disponibilidad_bitmap IN tkr_disponibilidad_bitmap%ROWTYPE,
        p_rowid                       IN VARCHAR2
    );

    -- 15. Actualizar todos los registros (Uso restringido)
    PROCEDURE p_actualizar_registros (
        pro_tkr_disponibilidad_bitmap IN tkr_disponibilidad_bitmap%ROWTYPE
    );

    -- 16. Obtener valores por defecto
    PROCEDURE p_valores_defecto (
        pro_tkr_disponibilidad_bitmap IN OUT tkr_disponibilidad_bitmap%ROWTYPE
    );

    -- 17. Verificar existencia y retornar JSON CLOB
    FUNCTION f_existe_json (
        p_id                          IN  tkr_disponibilidad_bitmap.id%TYPE,
        p_json_tkr_disponibilidad_bitmap OUT CLOB
    ) RETURN NUMBER;

    -- 18. Obtener JSON por PK (VARCHAR2 o CLOB según tamaño)
    FUNCTION f_json (
        p_id IN tkr_disponibilidad_bitmap.id%TYPE
    ) RETURN VARCHAR2;

    -- 19. Calcular total de páginas para paginación recibiendo JSON con campo "registros"
    FUNCTION f_total_paginas (
        p_json_entrada IN CLOB
    ) RETURN NUMBER;

    -- 20. Consultar registros paginados retornando JSON con información correspondiente
    FUNCTION f_consultar_paginado (
        p_pagina    IN NUMBER,
        p_registros IN NUMBER
    ) RETURN CLOB;

END PKGTKR_DISPONIBILIDAD_BITMAP_DAO;
/
