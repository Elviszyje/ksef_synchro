import { View, Text, StyleSheet } from 'react-native';
import { STATUS_LABELS, STATUS_BG_COLOR, STATUS_TEXT_COLOR } from '../../utils/statusColors';

interface Props {
  status: string;
}

export function StatusBadge({ status }: Props) {
  const bg = STATUS_BG_COLOR[status] ?? '#f3f4f6';
  const textColor = STATUS_TEXT_COLOR[status] ?? '#374151';
  const label = STATUS_LABELS[status] ?? status;
  return (
    <View style={[styles.badge, { backgroundColor: bg }]}>
      <Text style={[styles.text, { color: textColor }]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  badge: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
    alignSelf: 'flex-start',
  },
  text: {
    fontSize: 12,
    fontWeight: '500',
  },
});
