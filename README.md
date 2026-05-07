# tinder_but_photos

Swipe para limpiar tu galería. Sin servidores, sin subir tus fotos a ningún lado — todo corre local en tu iPhone.

Construido en ~2 horas después de ver una app de pago que hace lo mismo y no confiar en darle acceso a mis fotos a un tercero.

## Qué hace

- **Swipe izquierda** — la foto va a una pila de eliminación
- **Swipe derecha** — la guardas, no te la vuelve a mostrar
- **Swipe arriba** — la guarda en la carpeta **PawZone** (la más importante)
- Previsualiza la pila antes de borrar definitivamente, por si se te pasó alguna
- Filtra por carpetas
- Orden aleatorio para fotos y videos

## Requisitos

- iPhone con iOS 17+
- Mac con Xcode 16+
- Licencia de desarrollador Apple (gratuita para correrlo desde Xcode, **100 USD/año** para instalarlo permanentemente en el celu)

> Sin licencia paga, la app dura **7 días** en el dispositivo. Para reactivarla, reconecta el iPhone al Mac y vuelve a correrla desde Xcode.

## Cómo correrla

1. Clona el repo
2. Abre `tinder_but_photos.xcodeproj` en Xcode
3. Conecta tu iPhone
4. Selecciona tu dispositivo como destino y presiona ▶

Si es la primera vez, necesitás activar el **Modo Desarrollador** en el iPhone:  
`Ajustes → Privacidad y seguridad → Modo Desarrollador`

## Por qué es segura

Usa únicamente el framework `Photos` de Apple. No tiene red, no tiene backend, no manda nada a ningún servidor. Podés verificarlo — el código fuente está acá.

## Licencia

MIT — úsala, modifícala, distribúyela.
