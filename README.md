# Directorio de Profesionales - TEKER Medical Suite

Aplicación web de alto rendimiento y escalabilidad para la búsqueda y visualización de disponibilidad horaria de profesionales médicos con cálculo de intervalos y vector de bitmap sobre Oracle Database.

---

## 1. Características Principales
- **Filtros Multi-Criterio:** Búsqueda por especialidad, convenio, tipo de aseguramiento (Voluntario / Obligatorio) y modalidad de atención (Virtual / Domiciliaria).
- **Regla Estricta de Profesionales Habilitados:**
  - `id_estado_usuario = 1`.
  - Rol médico (`id_rol = 4` en `tkr_usuarios` o en `tkr_roles_usuario`).
  - Al menos una franja horaria activa registrada en `tkr_horarios_profesional`.
- **Motor de Jerarquía de Horarios:**
  - **Prioridad 1:** Horario por Día (`fecha_inicial = fecha_final = D`).
  - **Prioridad 2:** Horario Personalizado (`fecha_inicial <= D <= fecha_final`).
  - **Prioridad 3:** Horario Base permanente (`fecha_final IS NULL`).
- **Descuentos de Bloqueo:** Validación de ausencias (`tkr_ausencias_profesional`) y festivos/domingos sin autorización (`trabaja_festivos = 'N'`).
- **Vector de Bitmap:** Capacidad de generación y consulta binaria de 288 bits (1 bit = 5 minutos).
- **Paginación Server-Side:** Soporte nativo para miles de profesionales mediante `OFFSET ... FETCH NEXT`.

---

## 2. Scripts de Base de Datos (Ubicados en `database/`)
Todos los scripts han sido elaborados bajo el estándar `oracle-plsql-architecture` y documentados según `oracle-plsql-documentation`.

1. **`tkr_disponibilidad_bitmap.sql`**: Script DDL para la tabla de optimización de bitmaps de 288 bits e índices.
2. **`pkgcn_directorio_profesionales.pks` / `.pkb`**: Capa multi-tabla de negocio para filtrado, paginación y motor de slots.
3. **`pkgln_directorio_profesionales.pks` / `.pkb`**: Capa orquestadora transaccional con control de errores (`tkr_errores`), telemetría y payloads CLOB JSON.
4. **`pkgln_directorio_profesionales.md`**: Documentación funcional, bifurcaciones y mapa de objetos invocados.
5. **`pkgcn_directorio_profesionales.md`**: Documentación funcional en lenguaje natural de la información que trae y modifica cada método.

> [!NOTE]
> La compilación y ejecución de estos scripts en la base de datos es efectuada manualmente por el usuario.

---

## 3. Puesta en Marcha del Frontend
```bash
# Instalar dependencias
npm install

# Iniciar servidor de desarrollo
npm run dev
```
Acceder en el navegador a: `http://localhost:3000`
