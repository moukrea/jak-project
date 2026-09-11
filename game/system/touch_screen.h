#pragma once

// touch_screen — LE FAIT « CET APPAREIL A UN ECRAN TACTILE », POSE PAR LA PLATEFORME.
//
// POURQUOI. L'invite de l'ecran-titre doit dire « Appuie sur start ou touche l'ecran » quand on
// peut toucher l'ecran, et « Appuie sur start » sinon. La version precedente decidait a la
// CONSTRUCTION, en surchargeant la chaine #x16e dans une banque de texte « android » : la SHIELD,
// qui est Android et n'a pas d'ecran tactile, recevait donc l'invite tactile, et le jour ou le
// generateur de cette banque a ete archive l'override est tombe et TOUT Android est repasse a
// « Appuie sur start ». Le fait doit donc etre lu a l'EXECUTION, et par la plateforme elle-meme.
//
// LA SOURCE FAIT PARTIE DU FAIT. `kNone` ne veut pas dire « pas d'ecran tactile », il veut dire
// « personne n'a repondu » — c'est un defaut d'instrument, pas un appareil sans tactile. La porte
// de l'item compte donc `kNone` comme une erreur : sans cela, un binaire ou aucun ecrivain n'est
// compile rendrait « pas de tactile », donc « Appuie sur start », donc un vert par INACTION sur
// exactement le defaut qu'on corrige.

namespace touch_screen {

enum Source {
  kNone = 0,                    // personne n'a repondu : defaut d'instrument
  kAndroidPackageManager = 1,   // Java : PackageManager.hasSystemFeature(FEATURE_TOUCHSCREEN)
  kSdl = 2,                     // bureau : SDL_GetTouchDevices()
};

// Pose le fait. `input_devices` est un TEMOIN INDEPENDANT quand la plateforme peut en fournir un
// (Android : nombre de peripheriques InputDevice.SOURCE_TOUCHSCREEN, vu par InputManager et non
// par PackageManager) ; -1 = pas de temoin.
void set_present(bool present, Source source, int input_devices);

bool present();
Source source();
const char* source_name();
int input_devices();

}  // namespace touch_screen
