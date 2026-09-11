/* ============================================
   Los dos recorridos guiados (spec 030)
   ============================================

   Un stand es una persona con una laptop y una mesa; un estudiante es una
   persona con un telefono y cola detras. Son dos recorridos, no uno.

   Cada paso senala un elemento por su atributo data-tour, no por una clase de
   estilo: una clase se renombra al rediseniar una pantalla y el paso se queda
   apuntando al vacio sin que nada lo avise. El atributo existe solo para esto,
   asi que quien lo toque sabe lo que esta tocando.

   Ningun paso explica por que una pantalla es confusa. Si hiciera falta, lo que
   hay que cambiar es la pantalla.
   ============================================ */

export const TOUR_ESTUDIANTE = 'estudiante';
export const TOUR_STAND = 'stand';

export const PASOS_ESTUDIANTE = [
    {
        selector: '[data-tour="puntos"]',
        titulo: 'Estos son tus puntos',
        texto: 'Suman mientras recorres la feria y son los que cambias por premios. Empiezas en cero.',
    },
    {
        selector: '[data-tour="nav-scan"]',
        titulo: 'Escanea el código del stand',
        texto: 'Cada stand proyecta un código que cambia solo. Escanéalo desde acá y sumas puntos por la visita. Si la cámara no va, hay un código de seis caracteres para escribir.',
    },
    {
        selector: '[data-tour="nav-actividades"]',
        titulo: 'Participa en las actividades',
        texto: 'Cada comunidad organiza las suyas y valen más que una visita. Solo dan puntos mientras están en curso, así que conviene mirar acá qué está pasando ahora.',
    },
    {
        selector: '[data-tour="nav-premios"]',
        titulo: 'Canjea tus puntos',
        texto: 'Acá ves lo que hay y cuánto cuesta. El premio se retira en persona: muestras tu código en la mesa del stand y ellos confirman la entrega.',
    },
    {
        selector: '[data-tour="nav-ranking"]',
        titulo: 'Mira cómo vas',
        texto: 'El ranking se actualiza solo durante toda la feria. Tu fila aparece marcada para que la encuentres sin leer.',
    },
];

export const PASOS_STAND = [
    {
        selector: '[data-tour="qr"]',
        titulo: 'Proyecta tu código',
        texto: 'Es la forma de dar puntos: se muestra en una pantalla de tu mesa y cambia cada quince segundos, así que no sirve de nada fotografiarlo.',
    },
    {
        selector: '[data-tour="tab-actividades"]',
        titulo: 'Tus actividades',
        texto: 'Puedes crear hasta tres para todo el evento, y marcar una como evento principal: esa otorga 30 puntos y las demás 10. Solo dan puntos mientras las tengas iniciadas.',
    },
    {
        selector: '[data-tour="tab-premios"]',
        titulo: 'Tus premios',
        texto: 'Registra acá lo que trajiste y cuánto cuesta. Puedes reponer unidades en cualquier momento; para cambiar un precio ya publicado, lo hace la organización.',
    },
    {
        selector: '[data-tour="tab-canjes"]',
        titulo: 'Confirma una entrega',
        texto: 'El estudiante te muestra un código de seis caracteres. Lo escribes acá, eliges el premio y confirmas cuando ya se lo entregaste: ahí se le descuentan los puntos y sale una unidad del stock.',
    },
];
