import { View, Text, StyleSheet } from 'react-native';
import { colors } from '../../theme';

export function EmptyState({ message = 'Brak danych' }: { message?: string }) {
  return (
    <View style={styles.container}>
      <Text style={styles.text}>{message}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: 64 },
  text: { color: colors.gray400, fontSize: 16 },
});
