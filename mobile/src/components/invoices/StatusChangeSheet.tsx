import { useState } from 'react';
import { Modal, View, Text, TouchableOpacity, TextInput, ScrollView, StyleSheet } from 'react-native';
import { STATUS_LABELS } from '../../utils/statusColors';
import { colors, spacing, radius } from '../../theme';

interface Props {
  visible: boolean;
  onClose: () => void;
  allowedTransitions: string[];
  onConfirm: (status: string, note: string) => void;
}

export function StatusChangeSheet({ visible, onClose, allowedTransitions, onConfirm }: Props) {
  const [selected, setSelected] = useState<string>('');
  const [note, setNote] = useState('');

  const handleConfirm = () => {
    if (!selected) return;
    onConfirm(selected, note);
    setSelected('');
    setNote('');
  };

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.overlay}>
        <View style={styles.sheet}>
          <Text style={styles.title}>Zmień status</Text>
          <ScrollView>
            {allowedTransitions.map((s) => (
              <TouchableOpacity
                key={s}
                onPress={() => setSelected(s)}
                style={[styles.option, selected === s && styles.optionSelected]}
              >
                <Text style={[styles.optionText, selected === s && styles.optionTextSelected]}>
                  {STATUS_LABELS[s] ?? s}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
          <TextInput
            style={styles.noteInput}
            placeholder="Notatka (opcjonalna)"
            placeholderTextColor={colors.gray400}
            value={note}
            onChangeText={setNote}
            multiline
          />
          <View style={styles.buttons}>
            <TouchableOpacity onPress={onClose} style={styles.cancelBtn}>
              <Text style={styles.cancelText}>Anuluj</Text>
            </TouchableOpacity>
            <TouchableOpacity
              onPress={handleConfirm}
              disabled={!selected}
              style={[styles.confirmBtn, !selected && styles.confirmBtnDisabled]}
            >
              <Text style={[styles.confirmText, !selected && styles.confirmTextDisabled]}>Zapisz</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.4)' },
  sheet: { backgroundColor: colors.white, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg, padding: spacing.xl },
  title: { fontSize: 18, fontWeight: '700', color: colors.gray900, marginBottom: spacing.lg },
  option: { padding: spacing.lg, marginBottom: spacing.sm, borderRadius: radius.md, borderWidth: 2, borderColor: colors.gray200 },
  optionSelected: { borderColor: colors.primary, backgroundColor: colors.primaryLight },
  optionText: { color: colors.gray700, fontSize: 16 },
  optionTextSelected: { color: colors.primary, fontWeight: '600' },
  noteInput: { borderWidth: 1, borderColor: colors.gray300, borderRadius: radius.md, padding: spacing.md, marginTop: spacing.sm, color: colors.gray800, minHeight: 60 },
  buttons: { flexDirection: 'row', gap: spacing.md, marginTop: spacing.lg },
  cancelBtn: { flex: 1, padding: spacing.lg, borderWidth: 1, borderColor: colors.gray300, borderRadius: radius.md, alignItems: 'center' },
  cancelText: { color: colors.gray600, fontWeight: '500' },
  confirmBtn: { flex: 1, padding: spacing.lg, borderRadius: radius.md, alignItems: 'center', backgroundColor: colors.primary },
  confirmBtnDisabled: { backgroundColor: colors.gray200 },
  confirmText: { color: colors.white, fontWeight: '600' },
  confirmTextDisabled: { color: colors.gray400 },
});
